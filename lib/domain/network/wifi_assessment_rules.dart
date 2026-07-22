import 'wifi_technical_assessment.dart';

enum WifiAssessmentQuestion { nearby, connectionPossible, signal, internet }

class WifiAssessmentRuleState {
  const WifiAssessmentRuleState(this.visibleQuestions, this.requiredQuestions);
  final Set<WifiAssessmentQuestion> visibleQuestions;
  final Set<WifiAssessmentQuestion> requiredQuestions;
}

class WifiAssessmentValidationResult {
  const WifiAssessmentValidationResult(this.errors);
  final Map<WifiAssessmentQuestion, String> errors;
  bool get isValid => errors.isEmpty;
}

class WifiAssessmentRules {
  const WifiAssessmentRules._();

  static WifiAssessmentRuleState evaluate(WifiTechnicalAssessment value) {
    final visible = <WifiAssessmentQuestion>{WifiAssessmentQuestion.nearby};
    final required = <WifiAssessmentQuestion>{WifiAssessmentQuestion.nearby};
    if (value.wifiNearbyAnswer == TechnicalAssessmentAnswer.yes) {
      visible.add(WifiAssessmentQuestion.connectionPossible);
      required.add(WifiAssessmentQuestion.connectionPossible);
      if (value.wifiConnectionPossibleAnswer == TechnicalAssessmentAnswer.yes) {
        visible.addAll({
          WifiAssessmentQuestion.signal,
          WifiAssessmentQuestion.internet,
        });
        required.addAll({
          WifiAssessmentQuestion.signal,
          WifiAssessmentQuestion.internet,
        });
      }
    }
    return WifiAssessmentRuleState(visible, required);
  }

  static WifiTechnicalAssessment changeNearby(
    WifiTechnicalAssessment current,
    TechnicalAssessmentAnswer answer,
  ) {
    final becomingYes =
        current.wifiNearbyAnswer != TechnicalAssessmentAnswer.yes &&
        answer == TechnicalAssessmentAnswer.yes;
    return WifiTechnicalAssessment(
      wifiNearbyAnswer: answer,
      wifiConnectionPossibleAnswer: answer == TechnicalAssessmentAnswer.yes
          ? (becomingYes ? null : current.wifiConnectionPossibleAnswer)
          : TechnicalAssessmentAnswer.notApplicable,
      wifiSignalAdequateAnswer: answer == TechnicalAssessmentAnswer.yes
          ? (becomingYes ? null : current.wifiSignalAdequateAnswer)
          : TechnicalAssessmentAnswer.notApplicable,
      wifiInternetAvailableAnswer: answer == TechnicalAssessmentAnswer.yes
          ? (becomingYes ? null : current.wifiInternetAvailableAnswer)
          : TechnicalAssessmentAnswer.notApplicable,
      comments: answer == TechnicalAssessmentAnswer.yes ? current.comments : '',
      assessedBy: current.assessedBy,
      assessedAt: DateTime.now().toUtc(),
      schemaVersion: 2,
    );
  }

  static WifiTechnicalAssessment changeConnection(
    WifiTechnicalAssessment current,
    TechnicalAssessmentAnswer answer,
  ) {
    final becomingYes =
        current.wifiConnectionPossibleAnswer != TechnicalAssessmentAnswer.yes &&
        answer == TechnicalAssessmentAnswer.yes;
    return WifiTechnicalAssessment(
      wifiNearbyAnswer: current.wifiNearbyAnswer,
      wifiConnectionPossibleAnswer: answer,
      wifiSignalAdequateAnswer: answer == TechnicalAssessmentAnswer.yes
          ? (becomingYes ? null : current.wifiSignalAdequateAnswer)
          : TechnicalAssessmentAnswer.notApplicable,
      wifiInternetAvailableAnswer: answer == TechnicalAssessmentAnswer.yes
          ? (becomingYes ? null : current.wifiInternetAvailableAnswer)
          : TechnicalAssessmentAnswer.notApplicable,
      comments: current.comments,
      assessedBy: current.assessedBy,
      assessedAt: DateTime.now().toUtc(),
      schemaVersion: 2,
    );
  }

  static WifiTechnicalAssessment changeLeaf(
    WifiTechnicalAssessment current,
    WifiAssessmentQuestion question,
    TechnicalAssessmentAnswer answer,
  ) => WifiTechnicalAssessment(
    wifiNearbyAnswer: current.wifiNearbyAnswer,
    wifiConnectionPossibleAnswer: current.wifiConnectionPossibleAnswer,
    wifiSignalAdequateAnswer: question == WifiAssessmentQuestion.signal
        ? answer
        : current.wifiSignalAdequateAnswer,
    wifiInternetAvailableAnswer: question == WifiAssessmentQuestion.internet
        ? answer
        : current.wifiInternetAvailableAnswer,
    comments: current.comments,
    assessedBy: current.assessedBy,
    assessedAt: DateTime.now().toUtc(),
    schemaVersion: 2,
  );

  static WifiTechnicalAssessment changeComments(
    WifiTechnicalAssessment current,
    String comments,
  ) => WifiTechnicalAssessment(
    wifiNearbyAnswer: current.wifiNearbyAnswer,
    wifiConnectionPossibleAnswer: current.wifiConnectionPossibleAnswer,
    wifiSignalAdequateAnswer: current.wifiSignalAdequateAnswer,
    wifiInternetAvailableAnswer: current.wifiInternetAvailableAnswer,
    comments: comments,
    assessedBy: current.assessedBy,
    assessedAt: DateTime.now().toUtc(),
    schemaVersion: 2,
  );

  static WifiAssessmentValidationResult validate(
    WifiTechnicalAssessment value,
  ) {
    final state = evaluate(value);
    final answers = <WifiAssessmentQuestion, TechnicalAssessmentAnswer?>{
      WifiAssessmentQuestion.nearby: value.wifiNearbyAnswer,
      WifiAssessmentQuestion.connectionPossible:
          value.wifiConnectionPossibleAnswer,
      WifiAssessmentQuestion.signal: value.wifiSignalAdequateAnswer,
      WifiAssessmentQuestion.internet: value.wifiInternetAvailableAnswer,
    };
    final errors = <WifiAssessmentQuestion, String>{};
    for (final question in state.requiredQuestions) {
      if (answers[question] == null) {
        errors[question] = switch (question) {
          WifiAssessmentQuestion.nearby =>
            'Evalúa si hay una red Wi-Fi cercana.',
          WifiAssessmentQuestion.connectionPossible =>
            'Evalúa si es posible conectarse a Wi-Fi.',
          WifiAssessmentQuestion.signal =>
            'Evalúa si la señal Wi-Fi parece adecuada.',
          WifiAssessmentQuestion.internet =>
            'Evalúa si hay internet mediante Wi-Fi.',
        };
      }
    }
    return WifiAssessmentValidationResult(errors);
  }
}
