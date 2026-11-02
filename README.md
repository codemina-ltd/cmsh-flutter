# cmsh_flutter

Track the whole journey from a [CMSH.io](https://cmsh.io) short link into your
Flutter app: the click, the app open or install, who the user turned out to be,
and what they did next.

- Open the right screen from a link, on cold and warm start
- Keep the link through an install (deferred deep links)
- Connect user details you collect, such as name, phone and email, to the
  click that brought them
- Track in-app events, offline included

## Install

```bash
flutter pub add cmsh_flutter
```

Requires iOS 15 and Android 7 (API 24) or later.

## Set up

### 1. Register your app

In the CMSH portal, open **Apps**, add your app and copy its SDK key. The key is
safe to ship in your app: it can only send events for this app, and can't read
any data.

### 2. Start the SDK

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cmsh.init(sdkKey: 'pk_live_xxx');

  Cmsh.onLink.listen((link) {
    router.go(link.path);    // for example /product/1
    print(link.data);        // custom data set on the short link
  });

  runApp(const MyApp());
}
```

`onLink` covers cold starts, warm starts and deferred installs. A link that
arrives before you subscribe is held for you.

### 3. Connect your links to your app

Pick one, per link. You can use both.

#### Option A: `cmsh.io` links

No domain to set up on CMSH. The browser opens briefly, then your app.

1. Your own website must already open your app through
   [Universal Links](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
   and [App Links](https://developer.android.com/training/app-links).
2. Shorten one of those links in the portal and choose your app on the link.

CMSH records the click, then sends the user to your link with a `cmsh_click`
parameter added. This package reads it.

Some apps' in-app browsers won't open another app automatically, so CMSH may
show a small page with an **Open in app** button.

#### Option B: your own short domain

The app opens straight away with no browser step. Needs a custom domain on your
CMSH plan.

1. Verify a domain in the portal, such as `go.example.com`.
2. In **Apps**, assign the domain to your app, and fill in your Apple Team ID,
   bundle ID, Android package and SHA-256 signing fingerprints. CMSH serves the
   `apple-app-site-association` and `assetlinks.json` files for you.
3. Tell the package about the domain:

   ```dart
   await Cmsh.init(sdkKey: 'pk_live_xxx', domains: {'go.example.com'});
   ```

4. iOS: add `applinks:go.example.com` under **Associated Domains** in Xcode.
5. Android: add this inside your main activity:

   ```xml
   <intent-filter android:autoVerify="true">
     <action android:name="android.intent.action.VIEW" />
     <category android:name="android.intent.category.DEFAULT" />
     <category android:name="android.intent.category.BROWSABLE" />
     <data android:scheme="https" android:host="go.example.com" />
   </intent-filter>
   ```

Only hosts in `domains`, and links with a CMSH click on them, are sent to CMSH.
Your other deep links, which may hold things like reset tokens, stay on the
device.

## Identify users

A click can't tell you who someone is. Once the user signs in, send the fields
you need:

```dart
await Cmsh.identify('user_123', traits: {
  'name': 'Sara',
  'email': 'sara@example.com',
  'phone': '+447700900000',
  'plan': 'gold', // any field you need
});
```

Details are encrypted on our servers, and later calls merge. Everything the
device did before sign-in is linked to the same person.

On sign-out:

```dart
await Cmsh.reset();
```

Never put personal data in a link URL or its custom data. Anyone holding the
link can read those.

## Track events

```dart
await Cmsh.track('purchase', properties: {'value': 25, 'currency': 'GBP'});
```

Events are queued on the device and sent in batches, and they survive restarts.
Retries can't double count. Event names can't start with `$`.

## Deferred deep links

When the app isn't installed, the link still works after the install.

- **Android** is automatic, through the Play Install Referrer.
- **iOS** has no equivalent, so it needs a choice from you:

  ```dart
  await Cmsh.init(sdkKey: 'pk_live_xxx', iosClipboardMatching: true);
  ```

  CMSH's page copies a short code when the user taps **Get the app**, and the
  package reads it on first launch. iOS then shows a paste prompt to **every
  new user**, which is why this is off by default. If the user declines, or
  didn't pass through the page, the app opens normally.

## Privacy

You decide what you collect, and you're responsible for having a lawful basis.
CMSH processes the data on your behalf.

To wait for consent:

```dart
await Cmsh.init(sdkKey: 'pk_live_xxx', requireConsent: true);

// After the user agrees:
await Cmsh.setConsent(true);
```

Until then nothing is sent, though links still open the right screen. Revoking
deletes anything still queued on the device.

The device ID is a random value created by this package. It is not a hardware
or advertising identifier, and `reset` replaces it.

Declare what you send in Apple's privacy labels and Google Play's Data Safety
form. If you pass name, email or phone to `identify`, declare those too. The
package includes a `PrivacyInfo.xcprivacy` manifest for its own data.

To export or erase a person, use the portal or the API with your own user ID.

## Reliability

The package never throws to your app and never blocks it. If a request fails,
the event stays queued, and `onLink` still delivers a link built from the URL
with `isMatched` set to false. Pass `debug: true` to log failures. Logs never
include payloads.
