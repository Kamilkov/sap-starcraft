@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Planned Order'
define view entity ZI_SCEPlannedOrder
  as select from zsce_planord
  association        to parent ZI_SCEDivision as _Division on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game     on $projection.GameUUID = _Game.GameUUID
{
  key planord_uuid       as PlannedOrderUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      matnr              as Material,
      quantity           as Quantity,
      start_seconds      as StartSeconds,
      finish_seconds     as FinishSeconds,
      planned_for        as PlannedFor,
      exception_text     as ExceptionText,
      firmed             as Firmed,
      _Division,
      _Game
}
