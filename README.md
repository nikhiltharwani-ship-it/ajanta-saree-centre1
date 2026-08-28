# Ajanta Saree Centre Flutter V1

Starter Android/Flutter project for the agreed Ajanta Saree Centre architecture.

Included:
- Admin / Customer login UI (Customer ID + PIN, no OTP)
- Dashboard
- Sales screen with A/B/C selector
- Inventory entry
- Customer/Trader account area
- Purchases, returns, cashbook, reports, backup and settings navigation
- Local persistence foundation
- Clean architecture ready for Firebase/Firestore shared sync

To build:
1. Install Flutter.
2. Run `flutter pub get`.
3. Run `flutter run`.
4. For an APK: `flutter build apk`.

For two phones to share the same live database, connect Firebase Authentication + Cloud Firestore and add security rules. Do not put Firebase secrets or service-account credentials in the repository.
