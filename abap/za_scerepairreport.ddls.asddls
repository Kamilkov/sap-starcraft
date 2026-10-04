@EndUserText.label: 'SCE Repair Report Parameters'
define abstract entity ZA_SCERepairReport
{
  // RELEASED, STARTED, CONFIRMED or CANCELLED; a report carries the whole payload, so a skipped status loses nothing
  @EndUserText.label: 'Status'
  OrderStatus         : abap.char(10);
  @EndUserText.label: 'SCV tag'
  WorkerTag           : abap.int8;
  @EndUserText.label: 'Started at (s)'
  StartedAt           : abap.int4;
  // the game second of this report: the confirmation time of CONFIRMED, the closing time of a closed notification
  @EndUserText.label: 'At (s)'
  AtSeconds           : abap.int4;
  @EndUserText.label: 'Bot message'
  StatusText          : abap.char(80);
  // what becomes of the notification: blank keeps it, CANCELLED names OPEN or CLOSED, CONFIRMED always closes
  @EndUserText.label: 'Notification outcome'
  NotificationOutcome : abap.char(10);
}
