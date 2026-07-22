import 'package:ddr001diag/domain/network/wifi_assessment_rules.dart';
import 'package:ddr001diag/domain/network/wifi_technical_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const empty = WifiTechnicalAssessment(assessedBy: 'tech-1');

  test('No normaliza dependientes y deja de exigirlos', () {
    final value = WifiAssessmentRules.changeNearby(
      const WifiTechnicalAssessment(
        wifiNearbyAnswer: TechnicalAssessmentAnswer.yes,
        wifiConnectionPossibleAnswer: TechnicalAssessmentAnswer.yes,
        wifiSignalAdequateAnswer: TechnicalAssessmentAnswer.yes,
        wifiInternetAvailableAnswer: TechnicalAssessmentAnswer.yes,
        comments: 'dato anterior',
      ),
      TechnicalAssessmentAnswer.no,
    );

    expect(value.wifiConnectionPossibleAnswer, TechnicalAssessmentAnswer.notApplicable);
    expect(value.wifiSignalAdequateAnswer, TechnicalAssessmentAnswer.notApplicable);
    expect(value.wifiInternetAvailableAnswer, TechnicalAssessmentAnswer.notApplicable);
    expect(value.comments, isEmpty);
    expect(WifiAssessmentRules.validate(value).isValid, isTrue);
  });

  test('cambiar No a Sí no restaura respuestas obsoletas', () {
    final no = WifiAssessmentRules.changeNearby(empty, TechnicalAssessmentAnswer.no);
    final yes = WifiAssessmentRules.changeNearby(no, TechnicalAssessmentAnswer.yes);
    expect(yes.wifiConnectionPossibleAnswer, isNull);
    expect(yes.wifiSignalAdequateAnswer, isNull);
    expect(WifiAssessmentRules.validate(yes).errors.keys, [
      WifiAssessmentQuestion.connectionPossible,
    ]);
  });

  test('solo exige señal e internet cuando conexión es Sí', () {
    final nearby = WifiAssessmentRules.changeNearby(empty, TechnicalAssessmentAnswer.yes);
    final connected = WifiAssessmentRules.changeConnection(
      nearby,
      TechnicalAssessmentAnswer.yes,
    );
    expect(WifiAssessmentRules.evaluate(connected).requiredQuestions, containsAll([
      WifiAssessmentQuestion.signal,
      WifiAssessmentQuestion.internet,
    ]));

    final notVerified = WifiAssessmentRules.changeConnection(
      connected,
      TechnicalAssessmentAnswer.notVerified,
    );
    expect(notVerified.wifiSignalAdequateAnswer, TechnicalAssessmentAnswer.notApplicable);
    expect(WifiAssessmentRules.validate(notVerified).isValid, isTrue);
  });
}
