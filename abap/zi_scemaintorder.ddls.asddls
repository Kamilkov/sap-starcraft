@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Maintenance Order'
define view entity ZI_SCEMaintOrder
  as select from zsce_maintord
  association        to parent ZI_SCEDivision  as _Division    on $projection.DivisionUUID = _Division.DivisionUUID
  association [1..1] to ZI_SCEGame             as _Game        on $projection.GameUUID = _Game.GameUUID
  association [0..1] to ZI_SCEPlant            as _Plant       on $projection.PlantUUID = _Plant.PlantUUID
  association [0..1] to ZI_SCEMaterial         as _Material    on $projection.Material = _Material.Material
  association [0..1] to ZI_SCEOrderConsumption as _Consumption on $projection.OrderUUID = _Consumption.OrderUUID
  association [0..*] to ZI_SCEEvent            as _Event       on $projection.OrderUUID = _Event.OrderUUID
  association [0..1] to ZI_SCENotification     as _Notification on $projection.NotificationUUID = _Notification.NotificationUUID
{
  key order_uuid         as OrderUUID,
      division_uuid      as DivisionUUID,
      _Division.GameUUID as GameUUID,
      notif_uuid         as NotificationUUID,
      unit_tag           as UnitTag,
      matnr              as Material,
      plant_uuid         as PlantUUID,
      order_status       as OrderStatus,
      priority           as Priority,
      reported_at        as ReportedAt,
      released_at        as ReleasedAt,
      started_at         as StartedAt,
      confirmed_at       as ConfirmedAt,
      worker_tag         as WorkerTag,
      status_text        as StatusText,
      _Division,
      _Game,
      _Plant,
      _Material,
      _Consumption,
      _Event,
      _Notification
}
