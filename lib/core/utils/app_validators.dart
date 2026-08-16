class AppValidators {
  static String? Function(String?) required(String message) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Veuillez saisir un prix';
    }
    if (double.tryParse(value) == null) {
      return 'Veuillez saisir un nombre valide';
    }
    if (double.parse(value) < 0) {
      return 'Le prix ne peut pas être négatif';
    }
    return null;
  }
}
