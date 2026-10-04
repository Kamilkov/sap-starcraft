"! @testing ZI_SCEORDERVARIANCE
CLASS zcl_sce_variance_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS queued        TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000001'.
    CONSTANTS started       TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000002'.
    CONSTANTS overcharged   TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000003'.
    CONSTANTS waiting       TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000004'.
    CONSTANTS cancelledgame TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000005'.
    CONSTANTS scrapped      TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000006'.
    CONSTANTS cancelledsap  TYPE sysuuid_x16 VALUE 'F0000000000000000000000000000007'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS queue_wait_is_time_variance FOR TESTING.
    METHODS started_order_has_no_lead_time FOR TESTING.
    METHODS overcharge_is_price_variance FOR TESTING.
    METHODS released_order_stays_blank FOR TESTING.
    METHODS closed_orders_scrap_consumed FOR TESTING.
    METHODS sap_cancel_scraps_nothing FOR TESTING.
    METHODS live_orders_have_no_scrap FOR TESTING.
ENDCLASS.

CLASS zcl_sce_variance_test IMPLEMENTATION.
  METHOD class_setup.
    " unit mode: doubles zsce_prodord, zsce_material and ZI_SCEOrderConsumption
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCEORDERVARIANCE' ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    DATA orders TYPE STANDARD TABLE OF zsce_prodord WITH EMPTY KEY.
    DATA consumption TYPE STANDARD TABLE OF zi_sceorderconsumption WITH EMPTY KEY.
    env->clear_doubles( ).
    materials = VALUE #( bukrs = '1000'
      ( material_uuid = 'A0000000000000000000000000000001' matnr = 'Marine' category = 'UNIT'
        mineral_cost = 50 gas_cost = 0 build_seconds = 18 )
      ( material_uuid = 'A0000000000000000000000000000002' matnr = 'Marauder' category = 'UNIT'
        mineral_cost = 100 gas_cost = 25 build_seconds = 21 )
      ( material_uuid = 'A0000000000000000000000000000003' matnr = 'Barracks' category = 'STRUCTURE'
        mineral_cost = 150 gas_cost = 0 build_seconds = 46 )
      ( material_uuid = 'A0000000000000000000000000000004' matnr = 'SupplyDepot' category = 'STRUCTURE'
        mineral_cost = 100 gas_cost = 0 build_seconds = 21 ) ).
    orders = VALUE #( quantity = 1
      ( order_uuid = queued        matnr = 'Marine'      order_status = 'CONFIRMED' released_at = 10 confirmed_at = 100 )
      ( order_uuid = started       matnr = 'Marauder'    order_status = 'STARTED'   released_at = 20 )
      ( order_uuid = overcharged   matnr = 'Marine'      order_status = 'CONFIRMED' released_at = 5  confirmed_at = 23 )
      ( order_uuid = waiting       matnr = 'Marine'      order_status = 'RELEASED' )
      ( order_uuid = cancelledgame matnr = 'Barracks'    order_status = 'CANCELLED' released_at = 30 )
      ( order_uuid = scrapped      matnr = 'SupplyDepot' order_status = 'SCRAPPED'  released_at = 40 )
      ( order_uuid = cancelledsap  matnr = 'Marine'      order_status = 'CANCELLED' ) ).
    consumption = VALUE #(
      ( orderuuid = queued        consumedminerals = 50  consumedgas = 0 )
      ( orderuuid = started       consumedminerals = 100 consumedgas = 25 )
      ( orderuuid = overcharged   consumedminerals = 60  consumedgas = 0 )
      ( orderuuid = cancelledgame consumedminerals = 37  consumedgas = 0 )       " 261 150 - 262 113
      ( orderuuid = scrapped      consumedminerals = 100 consumedgas = 0 ) ).    " destroyed under construction
    env->insert_test_data( i_data = materials ).
    env->insert_test_data( i_data = orders ).
    env->insert_test_data( i_data = consumption ).
  ENDMETHOD.

  METHOD queue_wait_is_time_variance.
    " queued at 10, appeared at 100: lead 90 s against the standard 18 s
    SELECT SINGLE standardseconds, leadseconds, timevarianceseconds, mineralvariance, gasvariance
      FROM zi_sceordervariance WHERE orderuuid = @queued INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-standardseconds exp = 18 ).
    cl_abap_unit_assert=>assert_equals( act = row-leadseconds exp = 90 ).
    cl_abap_unit_assert=>assert_equals( act = row-timevarianceseconds exp = 72 ).
    cl_abap_unit_assert=>assert_equals( act = row-mineralvariance exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = row-gasvariance exp = 0 ).
  ENDMETHOD.

  METHOD started_order_has_no_lead_time.
    SELECT COUNT( * ) FROM zi_sceordervariance
      WHERE orderuuid = @started AND leadseconds IS NULL AND timevarianceseconds IS NULL
        AND mineralvariance = 0 AND gasvariance = 0
      INTO @DATA(n).
    cl_abap_unit_assert=>assert_equals( act = n exp = 1 msg = 'queued in the game, charged at standard, no lead time yet' ).
  ENDMETHOD.

  METHOD overcharge_is_price_variance.
    SELECT SINGLE timevarianceseconds, mineralvariance, gasvariance
      FROM zi_sceordervariance WHERE orderuuid = @overcharged INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-timevarianceseconds exp = 0 msg = 'built in standard time' ).
    cl_abap_unit_assert=>assert_equals( act = row-mineralvariance exp = 10 msg = '60 consumed against 50 standard' ).
    cl_abap_unit_assert=>assert_equals( act = row-gasvariance exp = 0 ).
  ENDMETHOD.

  METHOD released_order_stays_blank.
    SELECT COUNT( * ) FROM zi_sceordervariance
      WHERE orderuuid = @waiting AND standardseconds = 18
        AND leadseconds IS NULL AND timevarianceseconds IS NULL
        AND mineralvariance IS NULL AND gasvariance IS NULL
      INTO @DATA(n).
    cl_abap_unit_assert=>assert_equals( act = n exp = 1 msg = 'nothing consumed yet: no variance, not -50' ).
  ENDMETHOD.

  METHOD closed_orders_scrap_consumed.
    SELECT SINGLE scrapminerals, scrapgas FROM zi_sceordervariance WHERE orderuuid = @cancelledgame INTO @DATA(kept).
    cl_abap_unit_assert=>assert_equals( act = kept-scrapminerals exp = 37 msg = 'the 25% SC2 kept of a cancelled Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = kept-scrapgas exp = 0 ).
    SELECT SINGLE scrapminerals, scrapgas FROM zi_sceordervariance WHERE orderuuid = @scrapped INTO @DATA(lost).
    cl_abap_unit_assert=>assert_equals( act = lost-scrapminerals exp = 100 msg = 'destroyed under construction: all of it' ).
    cl_abap_unit_assert=>assert_equals( act = lost-scrapgas exp = 0 ).
    SELECT COUNT( * ) FROM zi_sceordervariance
      WHERE ( orderuuid = @cancelledgame OR orderuuid = @scrapped ) AND mineralvariance IS NULL AND gasvariance IS NULL
      INTO @DATA(n).
    cl_abap_unit_assert=>assert_equals( act = n exp = 2 msg = 'a closed order has scrap, not a price variance' ).
  ENDMETHOD.

  METHOD sap_cancel_scraps_nothing.
    SELECT COUNT( * ) FROM zi_sceordervariance
      WHERE orderuuid = @cancelledsap AND scrapminerals = 0 AND scrapgas = 0
      INTO @DATA(n).
    cl_abap_unit_assert=>assert_equals( act = n exp = 1 msg = 'never started: scrap 0, not blank' ).
  ENDMETHOD.

  METHOD live_orders_have_no_scrap.
    SELECT COUNT( * ) FROM zi_sceordervariance
      WHERE ( orderuuid = @queued OR orderuuid = @started OR orderuuid = @waiting )
        AND scrapminerals IS NULL AND scrapgas IS NULL
      INTO @DATA(n).
    cl_abap_unit_assert=>assert_equals( act = n exp = 3 msg = 'CONFIRMED, STARTED, RELEASED: no scrap' ).
  ENDMETHOD.
ENDCLASS.

