*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations

CLASS lhc_material DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR material RESULT result.
ENDCLASS.

CLASS lhc_material IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
ENDCLASS.
