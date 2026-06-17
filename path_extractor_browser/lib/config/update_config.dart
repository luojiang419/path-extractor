class AppUpdateConfig {
  const AppUpdateConfig({required this.owner, required this.repo});

  final String owner;
  final String repo;

  Uri get latestManifestUri => Uri.parse(
    'https://github.com/$owner/$repo/releases/latest/download/latest.json',
  );

  Uri get latestReleasePageUri =>
      Uri.parse('https://github.com/$owner/$repo/releases/latest');
}

const appUpdateConfig = AppUpdateConfig(
  owner: 'luojiang419',
  repo: 'path-extractor',
);
