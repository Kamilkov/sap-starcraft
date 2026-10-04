@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Stock Balance'
define view entity ZI_SCEStockBalance
  as select from zsce_event as e
    inner join   zsce_division as d on d.division_uuid = e.division_uuid
  association [0..1] to ZI_SCEMaterial as _Material on $projection.Material = _Material.Material
{
  key d.game_uuid     as GameUUID,
  key e.division_uuid as DivisionUUID,
  key e.plant_uuid    as PlantUUID,
  key e.matnr         as Material,
      sum( case e.mvt_type
             when '261' then 0 - e.quantity
             when '551' then 0 - e.quantity
             else e.quantity
           end )       as OnHand,
      _Material
}
group by
  d.game_uuid,
  e.division_uuid,
  e.plant_uuid,
  e.matnr
