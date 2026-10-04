@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Serial number (unit tag)'
define view entity ZI_SCESerialNumber
  as select from    ZI_SCESerialReceipt as Receipt
    inner join      ZI_SCETaggedEvent   as Event on Event.EventHex = Receipt.ReceiptHex
    left outer join ZI_SCESerialDeath   as Death on  Death.DivisionUUID = Receipt.DivisionUUID
                                                 and Death.UnitTag      = Receipt.UnitTag
  association [1..1] to ZI_SCEDivision as _Division on  $projection.DivisionUUID = _Division.DivisionUUID
  association [0..1] to ZI_SCEPlant    as _Plant    on  $projection.PlantUUID = _Plant.PlantUUID
  association [0..1] to ZI_SCEMaterial as _Material on  $projection.Material = _Material.Material
  association [0..*] to ZI_SCEEvent    as _Movement on  $projection.DivisionUUID = _Movement.DivisionUUID
                                                    and $projection.UnitTag      = _Movement.UnitTag
{
      // unique by construction: Receipt is grouped by the key, Event is joined by its own key, Death is grouped by the key.
      // Material, plant, order and source are the chosen receipt's own fields.
  key Receipt.DivisionUUID as DivisionUUID,
  key Receipt.UnitTag      as UnitTag,
      Event.Material       as Material,
      Event.Category       as Category,
      Event.PlantUUID      as PlantUUID,
      Event.OrderUUID      as OrderUUID,
      Event.EventUUID      as ReceiptEventUUID,
      Event.EventSource    as EventSource,
      Receipt.ReceivedAt   as ReceivedAt,
      Receipt.Receipts     as Receipts,
      Death.ScrappedAt     as ScrappedAt,
      cast( case when Death.UnitTag is null then 'IN_STOCK' else 'DESTROYED' end as abap.char( 10 ) ) as SerialStatus,
      _Division,
      _Plant,
      _Material,
      _Movement
}
