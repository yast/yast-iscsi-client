# Sources for iscsi-client

module_DATA = \
  modules/IscsiClientLib.rb \
  modules/IscsiClient.rb

client_DATA = \
  clients/iscsi-client.rb \
  clients/iscsi-client_auto.rb \
  clients/iscsi-client_proposal.rb \
  clients/iscsi-client_finish.rb \
  clients/inst_iscsi-client.rb

yncludedir = @yncludedir@/iscsi-client
ynclude_DATA = \
  include/iscsi-client/widgets.rb \
  include/iscsi-client/wizards.rb \
  include/iscsi-client/dialogs.rb \
  include/iscsi-client/complex.rb \
  include/iscsi-client/helps.rb

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/iscsi-client.rnc

desktop_DATA = \
  desktop/iscsi-client.desktop

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(schemafiles_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common