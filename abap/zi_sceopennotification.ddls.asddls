@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Open notification per equipment'
define view entity ZI_SCEOpenNotification
  as select from zsce_notif
{
      // the behaviour allows one notification that is not CLOSED per equipment; grouped, so that the equipment's
      // key stays unique whatever the table holds
  key division_uuid                                                    as DivisionUUID,
  key unit_tag                                                         as UnitTag,
      min( priority )                                                  as Priority,
      min( health )                                                    as Health,
      max( health_max )                                                as HealthMax,
      max( case notif_status when 'IN_PROCESS' then 1 else 0 end )     as InProcess,
      count(*)                                                         as OpenNotifications
}
where
  notif_status <> 'CLOSED'
group by
  division_uuid,
  unit_tag
