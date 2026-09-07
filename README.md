AJANTA SAREE CENTRE — FINAL BUILD FILES

Files:
- lib/main.dart       -> final application source
- pubspec.yaml        -> required Flutter packages
- firebase.json       -> Firebase Functions + Firestore configuration
- firestore.rules     -> production Firestore access rules
- functions/index.js  -> secure customer account creation/update/delete + legacy migration
- functions/package.json

Existing Firebase project setup:
- Keep the working android/app/google-services.json already in the project.
- Firebase Authentication: enable Firebase Authentication for the project. The app uses Firebase custom-token authentication via the included Cloud Functions; OTP is not used.
- Firestore database: create it in the existing Firebase project.

Authentication:
Admin IDs/PINs:
  nikhilasc / 0521
  kailashasc / 2105

Customer login remains Customer ID + PIN, with no OTP.
The customer PIN is converted internally into a stronger Firebase Auth password.

Cloud Functions:
From the Firebase project root:
  cd functions
  npm install
  cd ..
  firebase deploy --only functions,firestore:rules

Then build the Flutter app normally.

Important:
The final source was statically checked for bracket/parenthesis balance in this environment. Flutter/Dart CLI was not installed here, so a real flutter analyze/build could not be executed here. The user's current baseline had already built green before this final consolidation.
