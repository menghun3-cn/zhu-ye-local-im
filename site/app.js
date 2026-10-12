/* 官网脚本只做三件事：切主题、滚动入场、把最新版本的下载链接填上。
   不引第三方库、不做埋点、不读 Cookie。 */
(function () {
  'use strict';

  var REPO = 'menghun3-cn/zhu-ye-local-im';
  var RELEASES = 'https://github.com/' + REPO + '/releases';

  /* ---------------------------------------------------------------------
     主题：跟随系统开局（首屏内联脚本已经定过），这里只管手动切换与记住。
     --------------------------------------------------------------------- */
  var root = document.documentElement;
  var toggle = document.getElementById('themeToggle');
  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('lt-theme', next); } catch (e) { /* 隐私模式 */ }
    });
  }

  /* ---------------------------------------------------------------------
     入场：一次错峰序列。同一屏内按出现顺序各推 60ms，滚动过去才触发。
     prefers-reduced-motion 下全部直接显示，不做任何位移。
     --------------------------------------------------------------------- */
  var items = Array.prototype.slice.call(document.querySelectorAll('.reveal'));
  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function showAll() {
    items.forEach(function (el) { el.classList.add('in'); });
  }

  if (reduced || !('IntersectionObserver' in window)) {
    showAll();
  } else {
    var io = new IntersectionObserver(function (entries) {
      var shown = 0;
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        el.style.transitionDelay = (shown++ * 60) + 'ms';
        el.classList.add('in');
        io.unobserve(el);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    items.forEach(function (el) { io.observe(el); });
  }

  /* ---------------------------------------------------------------------
     最新版本：按钮默认都指向 releases/latest，能读到 API 时就换成具体产物。
     读不到（离线、被限流、还没有发布）就原样保留 —— 页面照常可用。

     附件里有两组「同一个结尾」的名字：带版本号的产物，和一份固定名（`-latest-`）
     别名（release.yml 两个都传，别名是给按固定地址拉包的外网机器用的）。后缀匹配会
     同时命中两者，谁排在前面谁被选上 —— 选到别名时，页面标签写着「最新版本 v0.1.1」、
     文件名里却没有版本号，前后自相矛盾。所以优先具体产物，别名只当没有它时的兜底。
     --------------------------------------------------------------------- */
  function isAlias(name) {
    return name.indexOf('-latest-') !== -1;
  }

  function bySuffix(assets, suffix) {
    var fallback = null;
    for (var i = 0; i < assets.length; i++) {
      var name = assets[i].name || '';
      if (name.length < suffix.length || name.slice(-suffix.length) !== suffix) continue;
      if (isAlias(name)) {
        if (!fallback) fallback = assets[i];
        continue;
      }
      return assets[i];
    }
    return fallback;
  }

  function fillRelease(release) {
    var version = String(release.tag_name || '').replace(/^v/, '');
    if (!version) return;

    var heroVersion = document.getElementById('heroVersion');
    if (heroVersion) heroVersion.textContent = '当前版本 v' + version;

    var releaseTag = document.getElementById('releaseTag');
    if (releaseTag) releaseTag.textContent = '最新版本 v' + version;

    var assets = release.assets || [];

    Array.prototype.forEach.call(document.querySelectorAll('[data-asset]'), function (el) {
      var hit = bySuffix(assets, el.getAttribute('data-asset'));
      if (!hit) return;
      el.setAttribute('href', hit.browser_download_url);
      el.setAttribute('rel', 'noopener');
    });

    Array.prototype.forEach.call(document.querySelectorAll('[data-asset-label]'), function (el) {
      var hit = bySuffix(assets, el.getAttribute('data-asset-label'));
      if (hit) el.textContent = hit.name;
    });

    // 主按钮给推荐的那一个：安装包。没有就退回绿色包。
    var heroDownload = document.getElementById('heroDownload');
    if (heroDownload) {
      var pick = bySuffix(assets, 'setup.exe') || bySuffix(assets, 'portable.zip');
      if (pick) heroDownload.setAttribute('href', pick.browser_download_url);
    }
  }

  if (!window.fetch) return;

  fetch('https://api.github.com/repos/' + REPO + '/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' }
  })
    .then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    })
    .then(fillRelease)
    .catch(function () {
      var releaseTag = document.getElementById('releaseTag');
      if (releaseTag) {
        releaseTag.textContent = '在 GitHub 上查看';
        releaseTag.style.cursor = 'pointer';
        releaseTag.addEventListener('click', function () { window.open(RELEASES, '_blank', 'noopener'); });
      }
    });
})();
