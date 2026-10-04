@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Serial number: scrapping (551)'
define view entity ZI_SCESerialDeath
  as select from ZI_SCETaggedEvent
{
  key DivisionUUID,
  key UnitTag,
      min( GameSeconds ) as ScrappedAt,
      count(*)           as Scrappings
}
where
  MovementType = '551'
group by
  DivisionUUID,
  UnitTag
