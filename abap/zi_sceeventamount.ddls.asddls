@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Goods Movement Amount per Currency'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_SCEEventAmount
  as select from    zsce_event    as Event
    left outer join zsce_material as Material on Material.matnr = Event.matnr
    left outer join zsce_prodord  as Ord      on Ord.order_uuid = Event.order_uuid
    left outer join zsce_maintord as Maint    on Maint.order_uuid = Event.order_uuid
{
  key Event.event_uuid                                 as EventUUID,
  key cast( 'MIN' as waers )                           as Currency,
      Event.division_uuid                              as DivisionUUID,
      Event.plant_uuid                                 as PlantUUID,
      Event.order_uuid                                 as OrderUUID,
      // CANCELLED / SCRAPPED: the aggregates count the order's consumption as scrap, not WIP
      Ord.order_status                                 as OrderStatus,
      // PM: the order is a maintenance order; its consumption is maintenance expense, never WIP
      cast( case when Maint.order_uuid is null then '' else 'PM' end as abap.char( 2 ) ) as OrderCategory,
      Event.mvt_type                                   as MovementType,
      Event.matnr                                      as Material,
      Material.category                                as Category,
      // plain dec, no currency semantics: CDS forbids 0 - <amount> in the aggregates' signed sums
      cast( Event.mineral_value as abap.dec( 15, 0 ) ) as Amount
}
union all select from zsce_event    as Event
    left outer join   zsce_material as Material on Material.matnr = Event.matnr
    left outer join   zsce_prodord  as Ord      on Ord.order_uuid = Event.order_uuid
    left outer join   zsce_maintord as Maint    on Maint.order_uuid = Event.order_uuid
{
  key Event.event_uuid                                 as EventUUID,
  key cast( 'GAS' as waers )                           as Currency,
      Event.division_uuid                              as DivisionUUID,
      Event.plant_uuid                                 as PlantUUID,
      Event.order_uuid                                 as OrderUUID,
      Ord.order_status                                 as OrderStatus,
      cast( case when Maint.order_uuid is null then '' else 'PM' end as abap.char( 2 ) ) as OrderCategory,
      Event.mvt_type                                   as MovementType,
      Event.matnr                                      as Material,
      Material.category                                as Category,
      cast( Event.gas_value as abap.dec( 15, 0 ) )     as Amount
}
