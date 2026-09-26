String checkoutError(Object error) {
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  return 'Lokale Speicherung fehlgeschlagen. Belege und Warenkorb prüfen, dann erneut versuchen.';
}
