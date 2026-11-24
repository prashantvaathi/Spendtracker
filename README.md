# Wealth Desk Android app (Flutter + AdMob): start here

This folder becomes your Android app. **GitHub builds it for you in the cloud.** You never install Flutter or Android Studio, and you never write code.

The app shows your Wealth Desk website inside a real Android app. On top of the website it adds:
- **AdMob ads:** a banner at the bottom, plus an optional full-screen ad. Pro users are ad-free.
- **Reminders** as real phone notifications.
- **UPI, WhatsApp, email and phone links** that open the right app.
- **The back button**, which closes pop-ups and goes back to Home.
- **PDF reports**, which you can save or print.

**Updates are automatic.** Anything you update through the website's Owner panel shows up in the app straight away. You only rebuild the app to change its name, icon or ad settings.

> First update your website to **v3.1 or newer** (Owner panel → App updates). The app needs it to work properly.

---

## Step 1: Put this folder on GitHub (once, about 10 minutes, on a laptop)

1. Create a free account at **github.com**.
2. Click **+** (top right) → **New repository**.
   - Name: `wealth-desk-android`
   - Choose **Private**. This matters, because your signing key will be stored here.
   - Click **Create repository**.
3. On the next page, click **uploading an existing file**.
4. Unzip `wealth-desk-android.zip` on your laptop. Open the unzipped folder, select **everything inside it**, and drag it onto the GitHub page. Then click **Commit changes**.
5. Check that GitHub shows a folder called **`.github`**.
   - **If it doesn't** (some computers hide folders that start with a dot), fix it like this:
     - Click **Add file → Create new file**.
     - Type the name `.github/workflows/1-create-signing-key.yml`.
     - Paste in the text from `COPY-OF-github-workflows/1-create-signing-key.yml`, then click **Commit**.
     - Do the same for `2-build-app.yml`.

## Step 2: Tell the app your website address

1. On GitHub, click **`wealthdesk_config.json`**, then the ✏️ pencil icon.
2. Change `https://YOUR-SUBDOMAIN.plutomonk.com/` to your real Wealth Desk address. Keep the quotes.
3. Click **Commit changes**.

That starts a build automatically. Open the **Actions** tab and wait for the green ✅ (about 10–15 minutes the first time).

**Test it:** click the finished run, scroll to **Artifacts**, download the zip and open **`WealthDesk-install-on-phone.apk`** on an Android phone. If the phone asks, allow "install unknown apps". You'll see Google **test** ads at first, which is normal.

## Step 3: Create your signing key (once)

1. **Actions** tab → **1 · Create signing key (run once)** → **Run workflow** → **Run workflow**.
2. When it finishes, download **SIGNING-KEY-keep-safe** from Artifacts.
   - **Save this zip in Google Drive and on a pen drive.** Without it you can never update your app on Google Play.
3. Repository **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add two secrets:
   - Name `KEYSTORE_BASE64`. Value: open `KEYSTORE_BASE64.txt`, then copy and paste everything in it.
   - Name `KEYSTORE_PASSWORD`. Value: everything inside `KEYSTORE_PASSWORD.txt`.
4. **Actions** → **2 · Build Android app** → **Run workflow**.

From now on, every build also gives you **`WealthDesk-upload-to-PlayStore.aab`**.

## Step 4: AdMob (your ad income)

1. Go to **admob.google.com** and sign in with your Google account.
2. **Apps → Add app → Android**.
   - Answer "No, it's not on Google Play yet".
   - App name: Wealth Desk.
3. Copy your **App ID**. It looks like `ca-app-pub-1234567890123456~1234567890`, with a **~**.
4. **Ad units → Add ad unit**:
   - **Banner** (required). Copy its ID. It looks like `ca-app-pub-…/1234567890`, with a **/**.
   - **Interstitial** (optional, the full-screen ad). Copy its ID too.
5. On GitHub, edit `wealthdesk_config.json` and replace the three `ca-app-pub-3940256099942544…` test IDs with yours. Commit, and a new build starts.
6. **app-ads.txt:** in your website's Owner panel → **Ads**, enter your **AdMob publisher ID** (`pub-1234567890123456`, shown in AdMob → Settings). The site then serves `/app-ads.txt` automatically. In your Play listing, set **Website** to your Wealth Desk address so AdMob can find it.

**Settings you can change** in `wealthdesk_config.json`:

| Setting | What it does |
|---|---|
| `show_banner_ad` | `true` shows the bottom banner, `false` hides it |
| `full_screen_ad_every_n_opens` | `0` = never. `3` = a full-screen ad every 3rd time the app is opened |
| `ads_for_pro_users` | `false` (recommended) means Pro users see no ads |
| `app_name`, `version` | The name under the icon, and the version shown on Google Play |

> ⚠️ Never tap your own ads, and don't ask friends to. AdMob bans accounts for this. To check that your real ads work, use a Basic (non-Pro) test account and just look.

## Step 5: Google Play

Upload **`WealthDesk-upload-to-PlayStore.aab`** in Play Console. Then follow the store-listing, data-safety and closed-testing steps in your **PLAY-STORE-GUIDE.txt**, with these changes:
- **Skip PWABuilder and assetlinks.** You don't need them for this app.
- **Data safety:** answer **"Contains ads: Yes"**. Under data types, add **"Device or other IDs → shared with Google for advertising"**.
- **App content → Advertising ID:** answer **Yes**, used for **Advertising**.
- **Already uploaded a PWABuilder version** with the same package name? Google will only accept this app if it's signed with the same key. Either use a new `package_id`, or ask Play support to reset your upload key. If you haven't uploaded anything yet, just use this app.

**Each new version for Google Play:**
1. Edit `version` in the config (for example `1.0.1`) and commit.
2. Download the new `.aab` and upload it in Play Console.

The build number goes up by itself.

---

### If a build fails

Open the failed run, click the red ❌ step and read the message. Most errors come from `wealthdesk_config.json`, and the message says exactly which line to fix. For anything else, copy the red error text and send it to Claude.
