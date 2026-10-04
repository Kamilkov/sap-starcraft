"! @testing ZI_SCEORDERCONSUMPTION
CLASS zcl_sce_consumption_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS retried  TYPE sysuuid_x16 VALUE 'B1000000000000000000000000000001'.
    CONSTANTS reversed TYPE sysuuid_x16 VALUE 'B1000000000000000000000000000002'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS retry_counts_once FOR TESTING.
    METHODS reversal_cancels_consumption FOR TESTING.
ENDCLASS.

CLASS zcl_sce_consumption_test IMPLEMENTATION.
  METHOD class_setup.
    " unit mode: doubles zsce_event
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCEORDERCONSUMPTION' ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    env->clear_doubles( ).
    events = VALUE #(
      " a Marine the game refused once: 261, reversed by 262, retried with 261, then received (101 carries the order too)
      ( event_uuid = 'E1000000000000000000000000000001' order_uuid = retried mvt_type = '261'
        matnr = 'MINERAL' quantity = 50 mineral_value = 50 )
      ( event_uuid = 'E1000000000000000000000000000002' order_uuid = retried mvt_type = '262'
        matnr = 'MINERAL' quantity = 50 mineral_value = 50 )
      ( event_uuid = 'E1000000000000000000000000000003' order_uuid = retried mvt_type = '261'
        matnr = 'MINERAL' quantity = 50 mineral_value = 50 )
      ( event_uuid = 'E1000000000000000000000000000004' order_uuid = retried mvt_type = '101'
        matnr = 'Marine' quantity = 1 mineral_value = 50 )
      " a Marauder refused and reversed, not started again yet
      ( event_uuid = 'E1000000000000000000000000000005' order_uuid = reversed mvt_type = '261'
        matnr = 'MINERAL' quantity = 100 mineral_value = 100 )
      ( event_uuid = 'E1000000000000000000000000000006' order_uuid = reversed mvt_type = '261'
        matnr = 'VESPENE' quantity = 25 gas_value = 25 )
      ( event_uuid = 'E1000000000000000000000000000007' order_uuid = reversed mvt_type = '262'
        matnr = 'MINERAL' quantity = 100 mineral_value = 100 )
      ( event_uuid = 'E1000000000000000000000000000008' order_uuid = reversed mvt_type = '262'
        matnr = 'VESPENE' quantity = 25 gas_value = 25 ) ).
    env->insert_test_data( i_data = events ).
  ENDMETHOD.

  METHOD retry_counts_once.
    SELECT SINGLE consumedminerals, consumedgas FROM zi_sceorderconsumption
      WHERE orderuuid = @retried INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-consumedminerals exp = 50
                                        msg = '261 50 - 262 50 + 261 50; the 101 is not consumption' ).
    cl_abap_unit_assert=>assert_equals( act = row-consumedgas exp = 0 ).
  ENDMETHOD.

  METHOD reversal_cancels_consumption.
    SELECT SINGLE consumedminerals, consumedgas FROM zi_sceorderconsumption
      WHERE orderuuid = @reversed INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-consumedminerals exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = row-consumedgas exp = 0 ).
  ENDMETHOD.
ENDCLASS.

