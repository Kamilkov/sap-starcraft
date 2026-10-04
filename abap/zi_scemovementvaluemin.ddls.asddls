@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Movement value in MIN (rate M)'
define view entity ZI_SCEMovementValueMin
  as select from ZI_SCEMovementAnalysis as M
    inner join   ZI_SCEMovementValue    as V on V.EventUUID = M.EventUUID
{
  key M.EventUUID,
      // minerals + gas at rate M; decfloat34 only inside, dec(15,0) out: decfloat34 would make OData 4.01
      cast( cast( M.Minerals as abap.decfloat34 ) + get_numeric_value( V.GasInMin ) as abap.dec( 15, 0 ) ) as ValueMin
}
