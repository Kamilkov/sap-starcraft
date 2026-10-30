"! @testing ZI_SCEDIVISIONARMYVALUE
CLASS zcl_sce_army_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS d1 TYPE sysuuid_x16 VALUE 'D1000000000000000000000000000A01'.
    CONSTANTS d2 TYPE sysuuid_x16 VALUE 'D2000000000000000000000000000A02'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    "! the currency_conversion double: GAS -> MIN at rate M (2); an input it does not list comes back as -1
    METHODS rate IMPORTING amount TYPE cl_cds_test_data=>cdsutf_amount
                           source TYPE waers
                           result TYPE cl_cds_test_data=>cdsutf_amount.
    METHODS army_value_of IMPORTING division TYPE sysuuid_x16 RETURNING VALUE(value) TYPE i.
    METHODS marauder_counts_gas_at_rate_m FOR TESTING.
    METHODS workers_are_not_army FOR TESTING.
ENDCLASS.

CLASS zcl_sce_army_test IMPLEMENTATION.
  METHOD class_setup.
    " unit mode: ZI_SCEEventAmount is doubled, and so is currency_conversion (rate M, GAS -> MIN = 2, as OB08)
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCEDIVISIONARMYVALUE' ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD rate.
    env->get_double( cl_cds_test_environment=>currency_conversion )->insert(
      cl_cds_test_data=>create_currency_conv_data( output = result )->for_parameters(
        amount             = amount
        source_currency    = source
        target_currency    = 'MIN'
        exchange_rate_date = sy-datum
        exchange_rate_type = 'M'
        error_handling     = 'SET_TO_NULL' ) ).
  ENDMETHOD.

  METHOD setup.
    DATA amounts TYPE STANDARD TABLE OF zi_sceeventamount WITH EMPTY KEY.
    env->clear_doubles( ).
    env->set_session_variables( VALUE #( ( name = if_cds_test_environment=>co_cds_session_system_date value = sy-datum ) ) ).
    " every amount that reaches the conversion is listed; the SCVs, the Command Center and the mining are filtered out before
    rate( amount = 200 source = 'MIN' result = 200 ).
    rate( amount = 100 source = 'MIN' result = 100 ).
    rate( amount = -50 source = 'MIN' result = -50 ).
    rate( amount = 25  source = 'GAS' result = 50 ).
    amounts = VALUE #(
      " D1 opening: 8 SCVs (workers), a Command Center (structure), 4 Marines
      ( eventuuid = 'E0000000000000000000000000000A01' currency = 'MIN' divisionuuid = d1
        movementtype = '561' material = 'SCV' category = 'UNIT' amount = 400 )
      ( eventuuid = 'E0000000000000000000000000000A02' currency = 'MIN' divisionuuid = d1
        movementtype = '561' material = 'CommandCenter' category = 'STRUCTURE' amount = 400 )
      ( eventuuid = 'E0000000000000000000000000000A03' currency = 'MIN' divisionuuid = d1
        movementtype = '561' material = 'Marine' category = 'UNIT' amount = 200 )
      " D1 mining and a Marauder built (100 MIN + 25 GAS = 150 MIN)
      ( eventuuid = 'E0000000000000000000000000000A04' currency = 'MIN' divisionuuid = d1
        movementtype = '501' material = 'MINERAL' category = 'RAW' amount = 500 )
      ( eventuuid = 'E0000000000000000000000000000A05' currency = 'MIN' divisionuuid = d1 orderstatus = 'CONFIRMED'
        movementtype = '101' material = 'Marauder' category = 'UNIT' amount = 100 )
      ( eventuuid = 'E0000000000000000000000000000A05' currency = 'GAS' divisionuuid = d1 orderstatus = 'CONFIRMED'
        movementtype = '101' material = 'Marauder' category = 'UNIT' amount = 25 )
      " D1 one Marine died
      ( eventuuid = 'E0000000000000000000000000000A06' currency = 'MIN' divisionuuid = d1
        movementtype = '551' material = 'Marine' category = 'UNIT' amount = 50 )
      " D2: 12 Probes (workers) and 2 Zealots at 100 each
      ( eventuuid = 'E0000000000000000000000000000B01' currency = 'MIN' divisionuuid = d2
        movementtype = '561' material = 'Probe' category = 'UNIT' amount = 600 )
      ( eventuuid = 'E0000000000000000000000000000B02' currency = 'MIN' divisionuuid = d2
        movementtype = '561' material = 'Zealot' category = 'UNIT' amount = 200 ) ).
    env->insert_test_data( i_data = amounts ).
  ENDMETHOD.

  METHOD army_value_of.
    SELECT SINGLE armyvaluemin FROM zi_scedivisionarmyvalue WHERE divisionuuid = @division INTO @value.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'no army value row' ).
  ENDMETHOD.

  METHOD marauder_counts_gas_at_rate_m.
    " 4 Marines 200 + Marauder (100 MIN + 25 GAS x 2) 150 - 1 Marine 50 = 300; the SCVs (400), the Command Center
    " (structure) and the mining (raw) are filtered out, so 300 also proves units only
    cl_abap_unit_assert=>assert_equals( act = army_value_of( d1 ) exp = 300 ).
  ENDMETHOD.

  METHOD workers_are_not_army.
    " 12 Probes (600) are workers; the 2 Zealots are the army
    cl_abap_unit_assert=>assert_equals( act = army_value_of( d2 ) exp = 200 ).
  ENDMETHOD.
ENDCLASS.

