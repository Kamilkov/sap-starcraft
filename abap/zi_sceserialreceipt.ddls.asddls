@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Serial number: the chosen receipt'
define view entity ZI_SCESerialReceipt
  as select from ZI_SCETaggedEvent as Event
    inner join   ZI_SCESerialFirst as First on  First.DivisionUUID = Event.DivisionUUID
                                            and First.UnitTag      = Event.UnitTag
                                            and First.ReceivedAt   = Event.GameSeconds
{
      // one receipt per division and tag: the earliest, the smallest UUID among equals.
      // Candidates are receipts only, so a 551 of the same second can never be chosen.
  key Event.DivisionUUID    as DivisionUUID,
  key Event.UnitTag         as UnitTag,
      min( Event.EventHex ) as ReceiptHex,
      min( First.ReceivedAt ) as ReceivedAt,
      min( First.Receipts )   as Receipts
}
where
     Event.MovementType = '101'
  or Event.MovementType = '561'
group by
  Event.DivisionUUID,
  Event.UnitTag
