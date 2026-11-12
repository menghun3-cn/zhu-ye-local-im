#ifndef RUNNER_FIREWALL_PROBE_H_
#define RUNNER_FIREWALL_PROBE_H_

#include <flutter/encodable_value.h>

// The name of the method channel the Dart side asks the firewall snapshot
// through. Kept next to the implementation so the two spellings cannot drift
// apart, the same rule kHostChannelName follows.
extern const char kFirewallChannelName[];

// Builds the snapshot Dart's firewall judgement consumes: the current
// network's category, whether that profile's firewall is enabled, and every
// enabled inbound allow rule with the fields the judgement reads.
//
// The work is plain COM -- INetFwPolicy2 for the rules and INetListManager for
// the network category -- which is the same policy store the PowerShell
// cmdlets read, minus the process spawn and the per-rule CIM round trips.
flutter::EncodableValue FirewallSnapshot();

#endif  // RUNNER_FIREWALL_PROBE_H_
