"! @testing ZI_SCESERIALNUMBER
"! @testing ZI_SCEEQUIPMENT
CLASS zcl_sce_serial_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS d1 TYPE sysuuid_x16 VALUE 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'.
    CONSTANTS d2 TYPE sysuuid_x16 VALUE 'D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2'.
    CONSTANTS p1 TYPE sysuuid_x16 VALUE 'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1'.
    CONSTANTS p2 TYPE sysuuid_x16 VALUE 'A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2'.
    CONSTANTS o1 TYPE sysuuid_x16 VALUE 'C1C1C1C1C1C1C1C1C1C1C1C1C1C1C1C1'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    "! one goods movement; the id becomes the event UUID, so a smaller id is the smaller UUID
    METHODS add IMPORTING id       TYPE i
                          division TYPE sysuuid_x16 DEFAULT d1
                          tag      TYPE zsce_event-unit_tag
                          mvt      TYPE zsce_event-mvt_type
                          material TYPE zsce_event-matnr
                          at       TYPE i DEFAULT 0
                          plant    TYPE sysuuid_x16 OPTIONAL
                          order    TYPE sysuuid_x16 OPTIONAL.
    METHODS post.
    METHODS receipt_gives_a_serial_number FOR TESTING.
    METHODS no_tag_no_serial_number FOR TESTING.
    METHODS scrapping_destroys FOR TESTING.
    METHODS scrapping_without_receipt FOR TESTING.
    METHODS divisions_stay_apart FOR TESTING.
    METHODS repeated_postings_give_one_row FOR TESTING.
    METHODS same_second_551_is_no_receipt FOR TESTING.
    METHODS only_structures_are_equipment FOR TESTING.
    METHODS equipment_status_follows FOR TESTING.
ENDCLASS.

CLASS zcl_sce_serial_test IMPLEMENTATION.
  METHOD class_setup.
    " the whole chain from the tables: the aggregation is what is under test
    env = cl_cds_test_environment=>create_for_multiple_cds(
            i_for_entities = VALUE #(
              ( i_for_entity      = 'ZI_SCESERIALNUMBER'
                i_dependency_list = VALUE #( ( 'ZSCE_EVENT' ) ( 'ZSCE_MATERIAL' ) ) )
              ( i_for_entity      = 'ZI_SCEEQUIPMENT'
                i_dependency_list = VALUE #( ( 'ZSCE_EVENT' ) ( 'ZSCE_MATERIAL' ) ( 'ZSCE_NOTIF' ) ) ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    env->clear_doubles( ).
    CLEAR events.
    " Barracks is stored twice: the material master is keyed by a UUID, not by the material
    materials = VALUE #( ( material_uuid = 'B0000000000000000000000000000001' matnr = 'Barracks' category = 'STRUCTURE' )
                         ( material_uuid = 'B0000000000000000000000000000002' matnr = 'Barracks' category = 'STRUCTURE' )
                         ( material_uuid = 'B0000000000000000000000000000003' matnr = 'Marine' category = 'UNIT' )
                         ( material_uuid = 'B0000000000000000000000000000004' matnr = 'MINERAL' category = 'RAW' )
                         ( material_uuid = 'B0000000000000000000000000000005' matnr = 'Stimpack' category = 'UPGRADE' ) ).
    env->insert_test_data( i_data = materials ).
  ENDMETHOD.

  METHOD add.
    APPEND VALUE #( event_uuid    = CONV sysuuid_x16( |E{ id WIDTH = 31 ALIGN = RIGHT PAD = '0' }| )
                    division_uuid = division
                    unit_tag      = tag
                    mvt_type      = mvt
                    matnr         = material
                    game_seconds  = at
                    plant_uuid    = plant
                    order_uuid    = order
                    quantity      = 1
                    event_source  = 'LIVE' ) TO events.
  ENDMETHOD.

  METHOD post.
    env->insert_test_data( i_data = events ).
  ENDMETHOD.

  METHOD receipt_gives_a_serial_number.
    add( id = 1 tag = 4001 mvt = '561' material = 'Marine' at = 0 plant = p1 ).
    add( id = 2 tag = 4002 mvt = '101' material = 'Barracks' at = 90 plant = p1 order = o1 ).
    post( ).
    SELECT * FROM zi_sceserialnumber ORDER BY unittag INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 msg = 'Barracks stored twice in the master must not double its row' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-material exp = 'Marine' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-serialstatus exp = 'IN_STOCK' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-material exp = 'Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-category exp = 'STRUCTURE' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-receivedat exp = 90 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-plantuuid exp = p1 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-orderuuid exp = o1 ).
    cl_abap_unit_assert=>assert_initial( act = rows[ 2 ]-scrappedat ).
  ENDMETHOD.

  METHOD no_tag_no_serial_number.
    " upgrades and raw materials carry no tag; a tagged one is still no serial number
    add( id = 1 tag = 0 mvt = '101' material = 'Marine' ).
    add( id = 2 tag = 0 mvt = '101' material = 'Stimpack' ).
    add( id = 3 tag = 4003 mvt = '101' material = 'Stimpack' ).
    add( id = 4 tag = 4004 mvt = '561' material = 'MINERAL' ).
    add( id = 5 tag = 4005 mvt = '101' material = 'Unknown' ).
    post( ).
    SELECT COUNT( * ) FROM zi_sceserialnumber INTO @DATA(total).
    cl_abap_unit_assert=>assert_equals( act = total exp = 0 ).
  ENDMETHOD.

  METHOD scrapping_destroys.
    add( id = 1 tag = 4001 mvt = '101' material = 'Marine' at = 30 plant = p1 ).
    add( id = 2 tag = 4001 mvt = '551' material = 'Marine' at = 200 plant = p1 ).
    post( ).
    SELECT SINGLE * FROM zi_sceserialnumber WHERE divisionuuid = @d1 AND unittag = 4001 INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-serialstatus exp = 'DESTROYED' ).
    cl_abap_unit_assert=>assert_equals( act = row-receivedat exp = 30 ).
    cl_abap_unit_assert=>assert_equals( act = row-scrappedat exp = 200 ).
  ENDMETHOD.

  METHOD scrapping_without_receipt.
    " the replay parser's building killed under construction: a lone 551
    add( id = 1 tag = 4001 mvt = '551' material = 'Barracks' at = 200 ).
    post( ).
    SELECT COUNT( * ) FROM zi_sceserialnumber INTO @DATA(total).
    cl_abap_unit_assert=>assert_equals( act = total exp = 0 ).
  ENDMETHOD.

  METHOD divisions_stay_apart.
    " tags repeat across games
    add( id = 1 division = d1 tag = 4001 mvt = '561' material = 'Marine' plant = p1 ).
    add( id = 2 division = d2 tag = 4001 mvt = '561' material = 'Barracks' plant = p2 ).
    add( id = 3 division = d2 tag = 4001 mvt = '551' material = 'Barracks' at = 50 plant = p2 ).
    post( ).
    SELECT * FROM zi_sceserialnumber ORDER BY divisionuuid INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-material exp = 'Marine' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-serialstatus exp = 'IN_STOCK' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-material exp = 'Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-serialstatus exp = 'DESTROYED' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-plantuuid exp = p2 ).
  ENDMETHOD.

  METHOD repeated_postings_give_one_row.
    " regression: the receipt posted twice (one of them later and at another plant), the 551 posted twice,
    " a tagged raw and a tagged upgrade receipt, and the material stored twice in the master
    add( id = 7 tag = 4001 mvt = '101' material = 'Barracks' at = 90 plant = p1 order = o1 ).
    add( id = 3 tag = 4001 mvt = '101' material = 'Barracks' at = 120 plant = p2 ).
    add( id = 9 tag = 4001 mvt = '101' material = 'Barracks' at = 90 plant = p2 ).
    add( id = 4 tag = 4001 mvt = '551' material = 'Barracks' at = 300 plant = p1 ).
    add( id = 5 tag = 4001 mvt = '551' material = 'Barracks' at = 310 plant = p1 ).
    add( id = 1 tag = 4001 mvt = '561' material = 'MINERAL' at = 0 ).
    add( id = 2 tag = 4001 mvt = '101' material = 'Stimpack' at = 10 ).
    post( ).
    SELECT * FROM zi_sceserialnumber INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 1 msg = 'the key must stay unique' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-material exp = 'Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-receivedat exp = 90 msg = 'the first receipt' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-receipteventuuid exp = CONV sysuuid_x16( 'E0000000000000000000000000000007' )
                                        msg = 'among the receipts of second 90 the smaller UUID' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-plantuuid exp = p1 msg = 'the plant of the chosen receipt' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-orderuuid exp = o1 msg = 'the order of the chosen receipt' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-receipts exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-serialstatus exp = 'DESTROYED' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-scrappedat exp = 300 ).
    SELECT COUNT( * ) FROM zi_sceequipment INTO @DATA(equipment).
    cl_abap_unit_assert=>assert_equals( act = equipment exp = 1 ).
  ENDMETHOD.

  METHOD same_second_551_is_no_receipt.
    " a 551 of the receipt's second with the smaller UUID must not be taken for the receipt
    add( id = 1 tag = 4001 mvt = '551' material = 'Barracks' at = 90 plant = p2 ).
    add( id = 2 tag = 4001 mvt = '101' material = 'Barracks' at = 90 plant = p1 order = o1 ).
    post( ).
    SELECT * FROM zi_sceserialnumber INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-receipteventuuid exp = CONV sysuuid_x16( 'E0000000000000000000000000000002' ) ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-plantuuid exp = p1 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-receipts exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-serialstatus exp = 'DESTROYED' ).
  ENDMETHOD.

  METHOD only_structures_are_equipment.
    add( id = 1 tag = 4001 mvt = '561' material = 'Marine' plant = p1 ).
    add( id = 2 tag = 4002 mvt = '101' material = 'Barracks' at = 90 plant = p1 ).
    add( id = 3 tag = 4003 mvt = '101' material = 'Barracks' at = 95 plant = p1 ).
    add( id = 4 tag = 4003 mvt = '551' material = 'Barracks' at = 400 plant = p1 ).
    post( ).
    SELECT * FROM zi_sceequipment ORDER BY unittag INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-unittag exp = 4002 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-equipmentstatus exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-equipmentstatus exp = 'DESTROYED' ).
  ENDMETHOD.

  METHOD equipment_status_follows.
    DATA notifications TYPE STANDARD TABLE OF zsce_notif WITH EMPTY KEY.
    add( id = 1 tag = 4001 mvt = '101' material = 'Barracks' at = 90 plant = p1 ).
    add( id = 2 tag = 4002 mvt = '101' material = 'Barracks' at = 91 plant = p1 ).
    add( id = 3 tag = 4003 mvt = '101' material = 'Barracks' at = 92 plant = p1 ).
    add( id = 4 tag = 4004 mvt = '101' material = 'Barracks' at = 93 plant = p1 ).
    add( id = 5 tag = 4004 mvt = '551' material = 'Barracks' at = 500 plant = p1 ).
    add( id = 6 division = d2 tag = 4001 mvt = '101' material = 'Barracks' at = 94 plant = p2 ).
    post( ).
    notifications = VALUE #(
      " 4001: repaired once, damaged again; and, against the rule, a second open one: still one equipment row
      ( notif_uuid = 'F0000000000000000000000000000001' division_uuid = d1 unit_tag = 4001 notif_status = 'CLOSED'
        priority = '1' health = 100 health_max = 1000 )
      ( notif_uuid = 'F0000000000000000000000000000002' division_uuid = d1 unit_tag = 4001 notif_status = 'OPEN'
        priority = '3' health = 900 health_max = 1000 )
      ( notif_uuid = 'F0000000000000000000000000000003' division_uuid = d1 unit_tag = 4001 notif_status = 'OPEN'
        priority = '2' health = 600 health_max = 1000 )
      " 4002: an order is released
      ( notif_uuid = 'F0000000000000000000000000000004' division_uuid = d1 unit_tag = 4002 notif_status = 'IN_PROCESS'
        priority = '1' health = 300 health_max = 1000 )
      " 4003: only history
      ( notif_uuid = 'F0000000000000000000000000000005' division_uuid = d1 unit_tag = 4003 notif_status = 'CLOSED'
        priority = '2' health = 500 health_max = 1000 )
      " 4004: destroyed with its notification still open
      ( notif_uuid = 'F0000000000000000000000000000006' division_uuid = d1 unit_tag = 4004 notif_status = 'OPEN'
        priority = '1' health = 10 health_max = 1000 ) ).
    env->insert_test_data( i_data = notifications ).

    SELECT * FROM zi_sceequipment ORDER BY divisionuuid, unittag INTO TABLE @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 5 msg = 'one row per equipment, whatever the notifications' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-equipmentstatus exp = 'DAMAGED' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-priority exp = '2' msg = 'the more urgent of the open ones' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ]-health exp = 600 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ]-equipmentstatus exp = 'IN_REPAIR' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 3 ]-equipmentstatus exp = 'OK' ).
    cl_abap_unit_assert=>assert_initial( act = rows[ 3 ]-health ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 4 ]-equipmentstatus exp = 'DESTROYED' ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 5 ]-divisionuuid exp = d2 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 5 ]-equipmentstatus exp = 'OK' msg = 'the same tag in another division' ).
  ENDMETHOD.
ENDCLASS.

