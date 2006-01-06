# Makefile.am for iscsi-client/src

yncludedir = @yncludedir@/iscsi-client

client_DATA =			\
	iscsi-client.ycp		\
	iscsi-client_auto.ycp	\
	iscsi-client_proposal.ycp

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp

desktop_DATA =			\
	iscsi-client.desktop

module_DATA =			\
	IscsiClient.ycp		\
	IscsiClient2.pm

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common
