@EndUserText.label: 'SCE Notification Report Parameters'
define abstract entity ZA_SCENotifReport
{
  // blank keeps the status (health and priority update), CLOSED closes the notification
  @EndUserText.label: 'Status'
  NotificationStatus : abap.char(10);
  @EndUserText.label: 'Priority'
  Priority           : abap.char(1);
  @EndUserText.label: 'Health'
  Health             : abap.int4;
  @EndUserText.label: 'Health max'
  HealthMax          : abap.int4;
  @EndUserText.label: 'At (s)'
  AtSeconds          : abap.int4;
  @EndUserText.label: 'Bot message'
  StatusText         : abap.char(80);
}
