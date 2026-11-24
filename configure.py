#!/usr/bin/env python3
"""Applies wealthdesk_config.json to the Android project. Run by GitHub Actions — you don't need to run it."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, *a)
def fail(msg):
    print('\n::error::' + msg + '\n'); sys.exit(1)

try:
    cfg = json.load(open(p('wealthdesk_config.json'), encoding='utf-8'))
except Exception as e:
    fail('wealthdesk_config.json is not valid. Check commas and quotes. Details: %s' % e)

url = str(cfg.get('website_url', '')).strip()
if 'YOUR-SUBDOMAIN' in url or not re.match(r'^https://[^/]+', url):
    fail('Set "website_url" in wealthdesk_config.json to your Wealth Desk address, e.g. https://money.plutomonk.com/ (must start with https://)')
if not url.endswith('/'): url += '/'
name = str(cfg.get('app_name', 'Wealth Desk')).strip() or 'Wealth Desk'
pkg = str(cfg.get('package_id', 'com.plutomonk.wealthdesk')).strip()
if not re.match(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){1,}$', pkg):
    fail('"package_id" must look like com.plutomonk.wealthdesk (lowercase letters, dots).')
ver = str(cfg.get('version', '1.0.0')).strip()
if not re.match(r'^\d+\.\d+\.\d+$', ver): fail('"version" must look like 1.0.0')
app_id = str(cfg.get('admob_app_id', '')).strip()
if not re.match(r'^ca-app-pub-\d+~\d+$', app_id):
    fail('"admob_app_id" must look like ca-app-pub-1234567890123456~1234567890 (AdMob → Apps → App settings). It contains a ~ sign.')
TEST = 'ca-app-pub-3940256099942544/'
banner = str(cfg.get('admob_banner_id', '')).strip()
inter = str(cfg.get('admob_interstitial_id', '')).strip()
app_open = str(cfg.get('admob_app_open_id', TEST + '9257395921' if '3940256099942544' in app_id else '')).strip()
rewarded = str(cfg.get('admob_rewarded_id', TEST + '5224354917' if '3940256099942544' in app_id else '')).strip()
for k, v in (('admob_banner_id', banner), ('admob_interstitial_id', inter), ('admob_app_open_id', app_open), ('admob_rewarded_id', rewarded)):
    if v and not re.match(r'^ca-app-pub-\d+/\d+$', v):
        fail('"%s" must look like ca-app-pub-1234567890123456/1234567890 (it contains a / sign), or be empty "".' % k)
def color(k, d):
    c = str(cfg.get(k, d)).strip().lstrip('#')
    if not re.match(r'^[0-9A-Fa-f]{6}$', c): fail('"%s" must be a colour like #F1F0E8' % k)
    return c.upper()
bg, brand = color('background_color', '#F1F0E8'), color('brand_color', '#FAE80A')
every = int(cfg.get('full_screen_ad_every_n_opens', 0) or 0)
app_open_hours = max(1, int(cfg.get('app_open_ad_every_hours', 4) or 4))
break_ads = bool(cfg.get('full_screen_ad_at_breaks', True))
remove_ads_reward = bool(cfg.get('remove_ads_reward', True))
show_banner = bool(cfg.get('show_banner_ad', True))
ads_pro = bool(cfg.get('ads_for_pro_users', False))
test_ids = '3940256099942544' in app_id

def esc(s): return s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
open(p('lib', 'config.dart'), 'w', encoding='utf-8').write(f"""// Generated from wealthdesk_config.json — edit that file instead.
class AppConfig {{
  static const String websiteUrl = '{esc(url)}';
  static const String appName = '{esc(name)}';
  static const String bannerId = '{esc(banner)}';
  static const String interstitialId = '{esc(inter)}';
  static const bool showBanner = {str(show_banner and bool(banner)).lower()};
  static const int interstitialEvery = {max(0, every) if inter else 0};
  static const bool adsForPro = {str(ads_pro).lower()};
  static const String appOpenId = '{esc(app_open)}';
  static const int appOpenHours = {app_open_hours};
  static const String rewardedId = '{esc(rewarded)}';
  static const bool breakAds = {str(break_ads and bool(inter)).lower()};
  static const bool removeAdsReward = {str(remove_ads_reward).lower()};
  static const int backgroundColor = 0xFF{bg};
  static const int brandColor = 0xFF{brand};
}}
""")

android = p('android')
if os.path.isdir(android):
    xml_name = name.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;')
    man = open(p('tool', 'templates', 'AndroidManifest.xml'), encoding='utf-8').read().replace('__APP_NAME__', xml_name).replace('__ADMOB_APP_ID__', app_id)
    open(p('android', 'app', 'src', 'main', 'AndroidManifest.xml'), 'w', encoding='utf-8').write(man)
    gradle = open(p('tool', 'templates', 'build.gradle'), encoding='utf-8').read().replace('__PACKAGE_ID__', pkg)
    for old in ('build.gradle.kts',):
        if os.path.exists(p('android', 'app', old)): os.remove(p('android', 'app', old))
    open(p('android', 'app', 'build.gradle'), 'w', encoding='utf-8').write(gradle)
    # newer Android Gradle Plugin + Kotlin so current plugins compile
    sg = p('android', 'settings.gradle')
    if os.path.exists(sg):
        s = open(sg, encoding='utf-8').read()
        s = re.sub(r'id "com.android.application" version "[^"]+"', 'id "com.android.application" version "8.3.2"', s)
        s = re.sub(r'id "org.jetbrains.kotlin.android" version "[^"]+"', 'id "org.jetbrains.kotlin.android" version "1.9.24"', s)
        open(sg, 'w', encoding='utf-8').write(s)
    gw = p('android', 'gradle', 'wrapper', 'gradle-wrapper.properties')
    if os.path.exists(gw):
        s = open(gw, encoding='utf-8').read()
        s = re.sub(r'distributionUrl=.*', r'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-all.zip', s)
        open(gw, 'w', encoding='utf-8').write(s)
    gp = p('android', 'gradle.properties')
    s = open(gp, encoding='utf-8').read() if os.path.exists(gp) else ''
    if 'org.gradle.jvmargs' not in s: s += '\norg.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:+HeapDumpOnOutOfMemoryError\n'
    if 'android.useAndroidX' not in s: s += 'android.useAndroidX=true\n'
    if 'android.enableJetifier' not in s: s += 'android.enableJetifier=true\n'
    open(gp, 'w', encoding='utf-8').write(s)

# version & colours for icons/splash
ps = open(p('pubspec.yaml'), encoding='utf-8').read()
ps = re.sub(r'^version: .*$', 'version: %s+1' % ver, ps, flags=re.M)
ps = re.sub(r'(adaptive_icon_background: )"#[0-9A-Fa-f]{6}"', r'\1"#%s"' % brand, ps)
ps = re.sub(r'(^\s*color: )"#[0-9A-Fa-f]{6}"', r'\1"#%s"' % bg, ps, flags=re.M)
open(p('pubspec.yaml'), 'w', encoding='utf-8').write(ps)

print('✓ Settings applied')
print('  Website:  ' + url)
print('  App name: ' + name)
print('  Package:  ' + pkg + '   Version: ' + ver)
print('  AdMob:    ' + ('Google TEST ads (replace with your own IDs before publishing)' if test_ids else 'your own IDs'))
summary = os.environ.get('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a', encoding='utf-8') as f:
        f.write('### Settings used\n\n| | |\n|---|---|\n| Website | %s |\n| App name | %s |\n| Package | `%s` |\n| Version | %s |\n| Ads | %s |\n\n' % (url, name, pkg, ver, '⚠️ Google **test** ads — put your own AdMob IDs in wealthdesk_config.json before publishing' if test_ids else 'Your AdMob IDs'))
