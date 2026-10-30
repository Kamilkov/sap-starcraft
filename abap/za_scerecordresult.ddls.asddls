@EndUserText.label: 'SCE Record Result Parameters'
define abstract entity ZA_SCERecordResult
{
  // blank winner and not void: a tie
  @EndUserText.label: 'Winner division'
  WinnerDivisionUUID : sysuuid_x16;
  @EndUserText.label: 'Duration (s)'
  DurationSeconds    : abap.int4;
  // a void match (no result) wins over any winner
  @EndUserText.label: 'Void'
  IsVoid             : abap_boolean;
}
