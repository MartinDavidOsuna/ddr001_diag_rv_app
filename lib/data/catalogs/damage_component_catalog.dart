abstract final class DamageComponentCatalog {
  static const schemaVersion = 1;
  static const components = [
    'Hidrante',
    'Puertas',
    'Medidor principal',
    'Válvula principal',
    'Manómetro principal',
    'Venturi',
    'Válvula 1',
    'Válvula 2',
    'Válvula 3',
    'Manómetro antes del filtro',
    'Manómetro después del filtro',
    'Filtro',
  ];
  static const statuses = {
    'noDamage': 'Sin daño',
    'damaged': 'Dañado',
    'notPresent': 'No existe',
    'notVerifiable': 'No verificable',
  };
}
