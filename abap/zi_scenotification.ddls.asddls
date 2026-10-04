@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Maintenance Notification'
define view entity ZI_SCENotification
  as select from zsce_notif
  association        to parent ZI_SCEDivision as _Division   on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame            as _Game       on $projection.GameUUID = _Game.GameUUID
  association [0..1] to ZI_SCEPlant           as _Plant      on $projection.PlantUUID = _Plant.PlantUUID
  association [0..1] to ZI_SCEMaterial        as _Material   on $projection.Material = _Material.Material
  association [0..*] to ZI_SCEMaintOrder      as _MaintOrder on $projection.NotificationUUID = _MaintOrder.NotificationUUID
{
  key notif_uuid         as NotificationUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      unit_tag           as UnitTag,
      matnr              as Material,
      plant_uuid         as PlantUUID,
      notif_status       as NotificationStatus,
      priority           as Priority,
      health             as Health,
      health_max         as HealthMax,
      reported_at        as ReportedAt,
      closed_at          as ClosedAt,
      status_text        as StatusText,
      _Division,
      _Game,
      _Plant,
      _Material,
      _MaintOrder
}
