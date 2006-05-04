# Makefile.am for iscsi-client/src

yncludedir = @yncludedir@/iscsi-client

client_DATA =			\
	iscsi-client.ycp		\
	iscsi-client_auto.ycp	\
	iscsi-client_proposal.ycp	\
	iscsi-client_finish.ycp		\
	inst_iscsi-client.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp		\
	widgets.ycp

desktop_DATA =			\
	iscsi-client.desktop

module_DATA =			\
	IscsiClient.ycp		

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common
