#include "firewall_probe.h"

#include <netlistmgr.h>
#include <netfw.h>
#include <objbase.h>
#include <wrl/client.h>

#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

const char kFirewallChannelName[] = "cn.hnasct.local_transfer/firewall";

namespace {

// UTF-16 -> UTF-8, for the BSTR fields COM hands back.
std::string WideToUtf8(const wchar_t* wide) {
  if (wide == nullptr || *wide == L'\0') {
    return std::string();
  }
  const int length = ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0,
                                           nullptr, nullptr);
  if (length <= 1) {
    return std::string();
  }
  std::string utf8(static_cast<size_t>(length - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8.data(), length, nullptr,
                        nullptr);
  return utf8;
}

// BSTRs the COM getters allocate have to be handed back.
struct Bstr {
  explicit Bstr(BSTR value) : value(value) {}
  ~Bstr() {
    if (value != nullptr) {
      ::SysFreeString(value);
    }
  }
  BSTR value;
};

// The category string Dart's parser already understands: the same names
// PowerShell's Get-NetConnectionProfile reported.
std::string CategoryName(NLM_NETWORK_CATEGORY category) {
  switch (category) {
    case NLM_NETWORK_CATEGORY_PUBLIC:
      return "Public";
    case NLM_NETWORK_CATEGORY_PRIVATE:
      return "Private";
    case NLM_NETWORK_CATEGORY_DOMAIN_AUTHENTICATED:
      return "DomainAuthenticated";
    default:
      return std::string();
  }
}

// Which INetFwPolicy2 profile flag a category maps to. Returns 0 when the
// category could not be determined, which callers treat as "do not guess".
NET_FW_PROFILE_TYPE2 ProfileFor(NLM_NETWORK_CATEGORY category) {
  switch (category) {
    case NLM_NETWORK_CATEGORY_PUBLIC:
      return NET_FW_PROFILE2_PUBLIC;
    case NLM_NETWORK_CATEGORY_PRIVATE:
      return NET_FW_PROFILE2_PRIVATE;
    case NLM_NETWORK_CATEGORY_DOMAIN_AUTHENTICATED:
      return NET_FW_PROFILE2_DOMAIN;
    default:
      return static_cast<NET_FW_PROFILE_TYPE2>(0);
  }
}

// "Domain, Private, Public" for the profile bits a rule carries. All three
// bits set means "any profile", which reads the same to the judgement.
std::string ProfileNames(long mask) {
  if ((mask & (NET_FW_PROFILE2_DOMAIN | NET_FW_PROFILE2_PRIVATE |
               NET_FW_PROFILE2_PUBLIC)) ==
      (NET_FW_PROFILE2_DOMAIN | NET_FW_PROFILE2_PRIVATE |
       NET_FW_PROFILE2_PUBLIC)) {
    return "Any";
  }
  std::string names;
  auto append = [&names](const char* name) {
    if (!names.empty()) {
      names += ", ";
    }
    names += name;
  };
  if (mask & NET_FW_PROFILE2_DOMAIN) {
    append("Domain");
  }
  if (mask & NET_FW_PROFILE2_PRIVATE) {
    append("Private");
  }
  if (mask & NET_FW_PROFILE2_PUBLIC) {
    append("Public");
  }
  return names;
}

flutter::EncodableValue RuleMap(INetFwRule* rule) {
  using flutter::EncodableMap;
  EncodableMap map;

  long protocol = 0;
  if (SUCCEEDED(rule->get_Protocol(&protocol))) {
    map[flutter::EncodableValue("proto")] =
        flutter::EncodableValue(std::to_string(protocol));
  }

  BSTR ports = nullptr;
  if (SUCCEEDED(rule->get_LocalPorts(&ports))) {
    Bstr guard(ports);
    const std::string text = WideToUtf8(ports);
    // An empty local-port list means every port, the same thing "Any" says.
    map[flutter::EncodableValue("port")] = flutter::EncodableValue(
        text.empty() ? std::string("Any") : text);
  }

  long profiles = 0;
  if (SUCCEEDED(rule->get_Profiles(&profiles))) {
    map[flutter::EncodableValue("prof")] =
        flutter::EncodableValue(ProfileNames(profiles));
  }

  BSTR app = nullptr;
  if (SUCCEEDED(rule->get_ApplicationName(&app))) {
    Bstr guard(app);
    map[flutter::EncodableValue("prog")] =
        flutter::EncodableValue(WideToUtf8(app));
  }

  BSTR service = nullptr;
  if (SUCCEEDED(rule->get_ServiceName(&service))) {
    Bstr guard(service);
    map[flutter::EncodableValue("svc")] =
        flutter::EncodableValue(WideToUtf8(service));
  }

  return flutter::EncodableValue(map);
}

// The current network's category, or an empty string when there is no
// connected network to ask about.
std::string CurrentNetworkCategory() {
  ComPtr<INetworkListManager> manager;
  if (FAILED(::CoCreateInstance(CLSID_NetworkListManager, nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&manager)))) {
    return std::string();
  }

  ComPtr<IEnumNetworks> networks;
  if (FAILED(manager->GetNetworks(NLM_ENUM_NETWORK_CONNECTED, &networks))) {
    return std::string();
  }

  // Only the first connected network matters: the judgement is about "can a
  // peer on this LAN reach us", and Windows reports one category per network
  // while multiple adapters share it in practice.
  ULONG fetched = 0;
  ComPtr<INetwork> network;
  if (FAILED(networks->Next(1, &network, &fetched)) || fetched == 0 ||
      network.Get() == nullptr) {
    return std::string();
  }

  NLM_NETWORK_CATEGORY category = NLM_NETWORK_CATEGORY_PUBLIC;
  if (FAILED(network->GetCategory(&category))) {
    return std::string();
  }
  return CategoryName(category);
}

}  // namespace

flutter::EncodableValue FirewallSnapshot() {
  using flutter::EncodableMap;
  using flutter::EncodableValue;

  // COM may already be initialised by the engine on this thread; either way
  // the calls below only need it to have happened once.
  const HRESULT initialized = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninitialize = SUCCEEDED(initialized);

  EncodableMap snapshot;

  ComPtr<INetFwPolicy2> policy;
  if (SUCCEEDED(::CoCreateInstance(CLSID_NetFwPolicy2, nullptr, CLSCTX_ALL,
                                   IID_PPV_ARGS(&policy)))) {
    const std::string category = CurrentNetworkCategory();
    snapshot[EncodableValue("category")] = EncodableValue(category);

    // Enabled-ness is only meaningful for the profile the current network
    // maps to; an unknown category leaves it null rather than guessing.
    const NET_FW_PROFILE_TYPE2 profile =
        category.empty() ? static_cast<NET_FW_PROFILE_TYPE2>(0)
                         : ProfileFor(
                               category == "Public"   ? NLM_NETWORK_CATEGORY_PUBLIC
                               : category == "Private"
                                   ? NLM_NETWORK_CATEGORY_PRIVATE
                                   : NLM_NETWORK_CATEGORY_DOMAIN_AUTHENTICATED);
    if (profile != static_cast<NET_FW_PROFILE_TYPE2>(0)) {
      VARIANT_BOOL enabled = VARIANT_FALSE;
      if (SUCCEEDED(policy->get_FirewallEnabled(profile, &enabled))) {
        snapshot[EncodableValue("enabled")] =
            EncodableValue(enabled == VARIANT_TRUE);
      }
    }

    ComPtr<INetFwRules> rules;
    if (SUCCEEDED(policy->get_Rules(&rules))) {
      ComPtr<IEnumVARIANT> enumerator;
      if (SUCCEEDED(rules->get__NewEnum(&enumerator))) {
        std::vector<EncodableValue> collected;
        // INetFwRules::Item takes a rule *name*, not an index, so the rules
        // are walked through the collection's IEnumVARIANT instead.
        for (;;) {
          VARIANT item;
          ::VariantInit(&item);
          ULONG fetched = 0;
          const HRESULT next = enumerator->Next(1, &item, &fetched);
          if (FAILED(next) || fetched == 0) {
            ::VariantClear(&item);
            break;
          }
          if (item.vt == VT_DISPATCH && item.pdispVal != nullptr) {
            ComPtr<INetFwRule> rule;
            if (SUCCEEDED(item.pdispVal->QueryInterface(IID_PPV_ARGS(&rule)))) {
              // The same filter the PowerShell query applied: only enabled
              // inbound allow rules can cover an inbound port.
              NET_FW_RULE_DIRECTION direction = NET_FW_RULE_DIR_OUT;
              NET_FW_ACTION action = NET_FW_ACTION_BLOCK;
              VARIANT_BOOL ruleEnabled = VARIANT_FALSE;
              if (SUCCEEDED(rule->get_Direction(&direction)) &&
                  direction == NET_FW_RULE_DIR_IN &&
                  SUCCEEDED(rule->get_Action(&action)) &&
                  action == NET_FW_ACTION_ALLOW &&
                  SUCCEEDED(rule->get_Enabled(&ruleEnabled)) &&
                  ruleEnabled == VARIANT_TRUE) {
                collected.push_back(RuleMap(rule.Get()));
              }
            }
          }
          ::VariantClear(&item);
        }
        snapshot[EncodableValue("rules")] = EncodableValue(collected);
      }
    }
  }

  if (uninitialize) {
    ::CoUninitialize();
  }
  return EncodableValue(snapshot);
}
