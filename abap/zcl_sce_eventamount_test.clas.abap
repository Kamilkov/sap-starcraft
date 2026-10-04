"! @testing ZI_SCEEVENTAMOUNT
CLASS zcl_sce_eventamount_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS marauder_event TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000001'.
    CONSTANTS mystery_event  TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000002'.
    CONSTANTS scrap_event    TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000003'.
    CONSTANTS scrapped_order TYPE sysuuid_x16 VALUE 'C0000000000000000000000000000001'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS each_event_gives_min_and_gas FOR TESTING.
    METHODS unknown_material_is_kept FOR TESTING.
    METHODS order_status_comes_along FOR TESTING.
    METHODS maintenance_order_is_marked FOR TESTING.
ENDCLASS.

CLASS zcl_sce_eventamount_test IMPLEMENTATION.
  METHOD class_setup.
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCEEVENTAMOUNT' ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    DATA orders TYPE STANDARD TABLE OF zsce_prodord WITH EMPTY KEY.
    env->clear_doubles( ).
    materials = VALUE #( ( material_uuid = 'A0000000000000000000000000000001' matnr = 'Marauder' category = 'UNIT' ) ).
    events = VALUE #( ( event_uuid = marauder_event division_uuid = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                        mvt_type = '101' matnr = 'Marauder' quantity = 1 mineral_value = 100 gas_value = 25 )
                      ( event_uuid = mystery_event division_uuid = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                        mvt_type = '561' matnr = 'Mystery' quantity = 1 mineral_value = 30 gas_value = 0 )
                      ( event_uuid = scrap_event division_uuid = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                        order_uuid = scrapped_order
                        mvt_type = '261' matnr = 'MINERAL' quantity = 100 mineral_value = 100 gas_value = 0 ) ).
    orders = VALUE #( ( order_uuid = scrapped_order matnr = 'SupplyDepot' quantity = 1 order_status = 'SCRAPPED' ) ).
    env->insert_test_data( i_data = materials ).
    env->insert_test_data( i_data = events ).
    env->insert_test_data( i_data = orders ).
  ENDMETHOD.

  METHOD each_event_gives_min_and_gas.
    SELECT currency, amount, category FROM zi_sceeventamount
      WHERE eventuuid = @marauder_event
      ORDER BY currency
      INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 msg = 'one MIN and one GAS row per event' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-currency exp = 'GAS' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( rows[ 1 ]-amount ) exp = 25 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-currency exp = 'MIN' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( rows[ 2 ]-amount ) exp = 100 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-category exp = 'UNIT' msg = 'category from the material master' ).
  ENDMETHOD.

  METHOD unknown_material_is_kept.
    SELECT currency, amount, category FROM zi_sceeventamount
      WHERE eventuuid = @mystery_event
      ORDER BY currency
      INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 msg = 'an unknown material must not drop the event' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( rows[ 2 ]-amount ) exp = 30 ).
    cl_abap_unit_assert=>assert_initial( act = rows[ 2 ]-category ).
    SELECT COUNT( * ) FROM zi_sceeventamount INTO @DATA(total).
    cl_abap_unit_assert=>assert_equals( act = total exp = 6 msg = '3 events x 2 currencies' ).
  ENDMETHOD.

  METHOD order_status_comes_along.
    " CANCELLED / SCRAPPED decide scrap in the aggregates; the join must neither drop nor double an event
    SELECT currency, orderstatus FROM zi_sceeventamount
      WHERE eventuuid = @scrap_event
      ORDER BY currency
      INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-orderstatus exp = 'SCRAPPED' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-orderstatus exp = 'SCRAPPED' ).
    SELECT SINGLE orderstatus FROM zi_sceeventamount
      WHERE eventuuid = @marauder_event AND currency = 'MIN'
      INTO @DATA(none).
    cl_abap_unit_assert=>assert_initial( act = none msg = 'an event without an order has no status' ).
  ENDMETHOD.

  METHOD maintenance_order_is_marked.
    " repair cost: the order of the 261 is a maintenance order; the join must neither drop nor double the event
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    DATA repairs TYPE STANDARD TABLE OF zsce_maintord WITH EMPTY KEY.
    events = VALUE #( ( event_uuid = 'E0000000000000000000000000000004' division_uuid = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                        order_uuid = 'C0000000000000000000000000000009'
                        mvt_type = '261' matnr = 'MINERAL' quantity = 13 mineral_value = 13 gas_value = 0 ) ).
    repairs = VALUE #( ( order_uuid = 'C0000000000000000000000000000009' division_uuid = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                         matnr = 'SupplyDepot' order_status = 'CONFIRMED' ) ).
    env->insert_test_data( i_data = events ).
    env->insert_test_data( i_data = repairs ).

    SELECT currency, ordercategory, orderstatus, amount FROM zi_sceeventamount
      WHERE eventuuid = 'E0000000000000000000000000000004'
      ORDER BY currency
      INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-ordercategory exp = 'PM' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-ordercategory exp = 'PM' ).
    cl_abap_unit_assert=>assert_initial( act = rows[ 2 ]-orderstatus msg = 'the status is the production order''s' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( rows[ 2 ]-amount ) exp = 13 ).
    SELECT COUNT( * ) FROM zi_sceeventamount WHERE ordercategory = 'PM' INTO @DATA(marked).
    cl_abap_unit_assert=>assert_equals( act = marked exp = 2 msg = 'production and order-less movements are not marked' ).
    SELECT COUNT( * ) FROM zi_sceeventamount INTO @DATA(total).
    cl_abap_unit_assert=>assert_equals( act = total exp = 8 msg = '4 events x 2 currencies' ).
  ENDMETHOD.
ENDCLASS.

