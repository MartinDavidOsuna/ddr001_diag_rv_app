import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'rv_work_dashboard.dart';

extension RvWorkGroupPresentation on RvWorkGroup {
  Color get color => switch (this) {
    RvWorkGroup.inProgress => AppColors.blue,
    RvWorkGroup.pendingSync => AppColors.orange,
    RvWorkGroup.submitted => AppColors.teal,
    RvWorkGroup.validated => AppColors.green,
    RvWorkGroup.returned || RvWorkGroup.conflicts => AppColors.red,
  };
}
