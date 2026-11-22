// Assimilis Mobile: PocketStrike started here as its own app. It now opens from the Assimilis hub
// (lib/hub/hub_view.dart) inside the shared ProviderScope set up in lib/main.dart.
// Its Telegram background relay is not started: PrivateLM already owns flutter_background_service.
export 'app/app.dart' show PocketStrikeApp;
export 'core/storage/prefs_provider.dart' show sharedPreferencesProvider;
