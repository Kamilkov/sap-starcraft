@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Planned Independent Requirement'
define view entity ZI_SCEPIR
  as select from zsce_pir
  association        to parent ZI_SCEDivision as _Division on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game     on $projection.GameUUID = _Game.GameUUID
{
  key pir_uuid           as RequirementUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      matnr              as Material,
      quantity           as Quantity,
      due_seconds        as DueSeconds,
      _Division,
      _Game
}
