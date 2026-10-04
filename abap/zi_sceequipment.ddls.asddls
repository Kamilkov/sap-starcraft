@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Equipment (structure)'
define view entity ZI_SCEEquipment
  as select from    ZI_SCESerialNumber     as Serial
    left outer join ZI_SCEOpenNotification as Damage on  Damage.DivisionUUID = Serial.DivisionUUID
                                                     and Damage.UnitTag      = Serial.UnitTag
  association [0..*] to ZI_SCENotification as _Notification on  $projection.DivisionUUID = _Notification.DivisionUUID
                                                            and $projection.UnitTag      = _Notification.UnitTag
  association [0..*] to ZI_SCEMaintOrder   as _MaintOrder   on  $projection.DivisionUUID = _MaintOrder.DivisionUUID
                                                            and $projection.UnitTag      = _MaintOrder.UnitTag
{
      // every serial number of a structure is an equipment; equipment number = serial number = unit tag
  key Serial.DivisionUUID as DivisionUUID,
  key Serial.UnitTag      as UnitTag,
      Serial.Material     as Material,
      Serial.PlantUUID    as PlantUUID,
      Serial.OrderUUID    as OrderUUID,
      Serial.EventSource  as EventSource,
      Serial.ReceivedAt   as ReceivedAt,
      Serial.ScrappedAt   as ScrappedAt,
      cast( case when Serial.SerialStatus = 'DESTROYED' then 'DESTROYED'
                 when Damage.InProcess = 1              then 'IN_REPAIR'
                 when Damage.UnitTag is not null        then 'DAMAGED'
                 else 'OK' end as abap.char( 10 ) ) as EquipmentStatus,
      Damage.Priority     as Priority,
      Damage.Health       as Health,
      Damage.HealthMax    as HealthMax,
      Serial._Division,
      Serial._Plant,
      Serial._Material,
      Serial._Movement,
      _Notification,
      _MaintOrder
}
where
  Serial.Category = 'STRUCTURE'
