abstract final class Routes {
  static const home = '/home';
  static const downloads = '/downloads';
  static const history = '/history';
  static const settings = '/settings';
  static const about = '/about';

  /// Older locations kept as redirects (Dashboard → Home; Queue → Downloads).
  static const dashboard = home;
  static const queue = '/queue';
}
