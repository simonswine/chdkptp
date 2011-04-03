# configurable build settings
# these can be set on the command line or in localbuildconf.inc
# should IUP gui be built ?
IUP_SUPPORT=0

# fill in the following, or install IUP to your system lib+include directories
#IUP_LIB_DIR=
#IUP_INCLUDE_DIR=

# for CHDK ptp.h this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
# so core/ptp.h should be found relative to this
# you do not need the whole chdk source, you can just copy ptp.h
CHDK_SRC_DIR=../trunk
LUA_INCLUDE_DIR=/usr/include/lua5.1
LUA_LIB=lua5.1

# compile with debug support 
DEBUG=1

