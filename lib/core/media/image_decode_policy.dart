import 'package:flutter/widgets.dart';

const int evidenceThumbnailDecodePixels = 192;
const int evidenceGridDecodePixels = 400;
const int maximumEvidenceViewerDecodePixels = 2048;

int evidenceViewerDecodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, maximumEvidenceViewerDecodePixels);
