class RtkReading {
  const RtkReading({required this.label, required this.simulated});
  final String label;
  final bool simulated;
}

abstract interface class RtkService {
  RtkReading get status;
}

class SimulatedRtkService implements RtkService {
  @override
  RtkReading get status =>
      const RtkReading(label: 'RTK simulado · no disponible', simulated: true);
}
