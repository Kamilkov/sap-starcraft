@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Plant'
define view entity ZI_SCEPlant
  as select from zsce_plant
  association        to parent ZI_SCEDivision as _Division on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game     on $projection.GameUUID = _Game.GameUUID
{
  key plant_uuid         as PlantUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      plant_code         as PlantCode,
      pos_x              as PosX,
      pos_y              as PosY,
      founded_at         as FoundedAt,
      closed_at          as ClosedAt,
      _Division,
      _Game
}
