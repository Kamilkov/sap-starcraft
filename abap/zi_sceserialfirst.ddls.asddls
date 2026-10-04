@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Serial number: first receipt time'
define view entity ZI_SCESerialFirst
  as select from ZI_SCETaggedEvent
{
  key DivisionUUID,
  key UnitTag,
      min( GameSeconds ) as ReceivedAt,
      count(*)           as Receipts
}
where
     MovementType = '101'
  or MovementType = '561'
group by
  DivisionUUID,
  UnitTag
