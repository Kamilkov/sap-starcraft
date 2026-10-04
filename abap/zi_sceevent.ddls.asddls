@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Goods Movement'
define view entity ZI_SCEEvent
  as select from zsce_event
  association        to parent ZI_SCEDivision as _Division  on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game      on $projection.GameUUID = _Game.GameUUID
  association [0..1] to ZI_SCEPlant           as _Plant     on $projection.PlantUUID = _Plant.PlantUUID
  association [0..1] to ZI_SCEProdOrder       as _ProdOrder on $projection.OrderUUID = _ProdOrder.OrderUUID
  association [0..1] to ZI_SCEMaterial        as _Material  on $projection.Material = _Material.Material
{
  key event_uuid         as EventUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      plant_uuid         as PlantUUID,
      order_uuid         as OrderUUID,
      game_seconds       as GameSeconds,
      mvt_type           as MovementType,
      matnr              as Material,
      quantity           as Quantity,
      mineral_value      as MineralValue,
      gas_value          as GasValue,
      event_source       as EventSource,
      unit_tag           as UnitTag,
      _Division,
      _Game,
      _Plant,
      _ProdOrder,
      _Material
}
