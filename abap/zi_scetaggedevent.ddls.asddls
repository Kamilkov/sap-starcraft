@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Goods movement of a serialized item'
define view entity ZI_SCETaggedEvent
  as select from zsce_event             as Event
    inner join   ZI_SCEMaterialCategory as Material on Material.Material = Event.matnr
{
      // one row per event: the join partner is grouped by its join column
  key Event.event_uuid             as EventUUID,
      // character form of the key: min() picks one receipt per tag, and RAW cannot be aggregated
      bintohex( Event.event_uuid ) as EventHex,
      Event.division_uuid          as DivisionUUID,
      Event.unit_tag               as UnitTag,
      Event.mvt_type               as MovementType,
      Event.matnr                  as Material,
      Material.Category            as Category,
      Event.plant_uuid             as PlantUUID,
      Event.order_uuid             as OrderUUID,
      Event.game_seconds           as GameSeconds,
      Event.event_source           as EventSource
}
where
       Event.unit_tag    > 0
  and(
       Material.Category = 'UNIT'
    or Material.Category = 'STRUCTURE'
  )
  and(
       Event.mvt_type    = '101'
    or Event.mvt_type    = '561'
    or Event.mvt_type    = '551'
  )
