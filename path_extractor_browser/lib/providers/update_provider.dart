import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/update_config.dart';
import '../services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(config: appUpdateConfig),
);
