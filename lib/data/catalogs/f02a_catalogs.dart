abstract final class F02aCatalogs {
  static const schemaVersion = 1;
  static const accessTypes = ['Vehicular', 'Peatonal', 'Ambos'];
  static const conditions = [
    'Bueno',
    'Regular',
    'Malo',
    'Crítico',
    'No verificado',
  ];
  static const diameters = [
    '2 pulgadas',
    '3 pulgadas',
    '4 pulgadas',
    '6 pulgadas',
    '8 pulgadas',
    'Otro',
    'No identificable',
  ];
  static const damageCategories = [
    'Fuga',
    'Corrosión',
    'Tubería dañada',
    'Brida dañada',
    'Conexión deteriorada',
    'Medidor dañado',
    'Válvula dañada',
    'Solenoide dañado',
    'Gabinete dañado',
    'Tapa faltante',
    'Obra civil dañada',
    'Inundación',
    'Vegetación',
    'Vandalismo',
    'Componente faltante',
    'Cableado expuesto',
    'Condición insegura',
    'Otro',
  ];
  static const components = [
    'Salida',
    'Válvula',
    'Medidor',
    'Válvula reductora',
    'Filtro',
    'Solenoide',
    'Gabinete',
    'Controlador',
    'Fuente de energía',
    'Módem',
    'Antena',
    'Otro',
  ];
  static const unassignedReasons = [
    'Encontrado durante recorrido',
    'Apoyo a otra brigada',
    'Asignación incorrecta',
    'Atención urgente',
    'Instrucción del supervisor',
    'Otro',
  ];
  static const energySources = [
    'Red eléctrica',
    'Panel solar',
    'Batería',
    'Transformador',
    'Otra',
  ];
  static const communications = [
    '2G',
    '3G',
    '4G',
    '5G',
    'Wi-Fi',
    'Radio',
    'Otra',
  ];
  static const classifications = [
    'Operativo',
    'Operativo con observaciones',
    'No operativo',
    'Riesgo crítico',
  ];
}
