@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Production Order'
define view entity ZI_SCEProdOrder
  as select from zsce_prodord
  association        to parent ZI_SCEDivision as _Division on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game     on $projection.GameUUID = _Game.GameUUID
  association [0..1] to ZI_SCEPlant           as _Plant    on $projection.PlantUUID = _Plant.PlantUUID
  association [0..1] to ZI_SCEMaterial        as _Material on $projection.Material = _Material.Material
  association [0..1] to ZI_SCEOrderVarianceMin as _Variance on $projection.OrderUUID = _Variance.OrderUUID
{
  key order_uuid         as OrderUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      plant_uuid         as PlantUUID,
      matnr              as Material,
      quantity           as Quantity,
      order_status       as OrderStatus,
      released_at        as ReleasedAt,
      confirmed_at       as ConfirmedAt,
      unit_tag           as UnitTag,
      status_text        as StatusText,
      _Division,
      _Game,
      _Plant,
      _Material,
      _Variance
}
