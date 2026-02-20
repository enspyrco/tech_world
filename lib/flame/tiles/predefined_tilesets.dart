import 'package:tech_world/flame/tiles/tileset.dart';

/// Test tileset — a 4x4 grid of colored 32x32 squares for development.
const testTileset = Tileset(
  id: 'test',
  name: 'Test Tileset',
  imagePath: 'tilesets/test_tileset.png',
  tileSize: 32,
  columns: 4,
  rows: 4,
);

// ---------------------------------------------------------------------------
// Modern Office Revamped (LimeZu)
// ---------------------------------------------------------------------------

/// Room Builder Office — walls, floors, furniture foundations (16×14 = 224 tiles).
const roomBuilderOffice = Tileset(
  id: 'room_builder_office',
  name: 'Room Builder Office',
  imagePath: 'tilesets/room_builder_office.png',
  tileSize: 32,
  columns: 16,
  rows: 14,
);

/// Modern Office — desks, chairs, computers, decorations (16×53 = 848 tiles).
const modernOffice = Tileset(
  id: 'modern_office',
  name: 'Modern Office',
  imagePath: 'tilesets/modern_office.png',
  tileSize: 32,
  columns: 16,
  rows: 53,
);

// ---------------------------------------------------------------------------
// Modern Exteriors (LimeZu)
// ---------------------------------------------------------------------------

/// Terrains & Fences — grass, dirt, paths, fences (32×74).
const extTerrains = Tileset(
  id: 'ext_terrains',
  name: 'Ext: Terrains & Fences',
  imagePath: 'tilesets/ext_terrains.png',
  tileSize: 32,
  columns: 32,
  rows: 74,
);

/// Worksite — construction props, barriers, equipment (32×20).
const extWorksite = Tileset(
  id: 'ext_worksite',
  name: 'Ext: Worksite',
  imagePath: 'tilesets/ext_worksite.png',
  tileSize: 32,
  columns: 32,
  rows: 20,
);

/// Hotel & Hospital — medical/hotel furniture and walls (32×62).
const extHotelHospital = Tileset(
  id: 'ext_hotel_hospital',
  name: 'Ext: Hotel & Hospital',
  imagePath: 'tilesets/ext_hotel_hospital.png',
  tileSize: 32,
  columns: 32,
  rows: 62,
);

/// School — classrooms, desks, school props (32×116).
const extSchool = Tileset(
  id: 'ext_school',
  name: 'Ext: School',
  imagePath: 'tilesets/ext_school.png',
  tileSize: 32,
  columns: 32,
  rows: 116,
);

/// Office — exterior office buildings, signage, props (32×95).
const extOffice = Tileset(
  id: 'ext_office',
  name: 'Ext: Office',
  imagePath: 'tilesets/ext_office.png',
  tileSize: 32,
  columns: 32,
  rows: 95,
);

/// All available tilesets.
const allTilesets = [
  testTileset,
  roomBuilderOffice,
  modernOffice,
  extTerrains,
  extWorksite,
  extHotelHospital,
  extSchool,
  extOffice,
];
