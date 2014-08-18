#
# spec file for package yast2-iscsi-client
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-iscsi-client
Version:        3.1.15
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:	        System/YaST
License:        GPL-2.0
# Service module switched to systemd
BuildRequires:	yast2 >= 2.23.15
BuildRequires:	docbook-xsl-stylesheets doxygen libxslt perl-XML-Writer popt-devel sgml-skel update-desktop-files yast2-packagemanager-devel yast2-perl-bindings yast2-testsuite libicu-devel yast2-packager
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  rubygem-rspec

Requires:	yast2-packager

# network needs Wizard::OpenCancelOKDialog()
#  function from yast2-2.18.2
# Wizard::SetDesktopTitleAndIcon
Requires:       yast2 >= 2.21.22

BuildArchitectures:	noarch

Requires:       yast2-ruby-bindings >= 3.1.7
Requires:       open-iscsi
Requires:       iscsiuio

Summary:	YaST2 - iSCSI Client Configuration

%description
This package contains the YaST2 component for configuration of an iSCSI
client.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install


%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/iscsi-client
%{yast_yncludedir}/iscsi-client/*
%{yast_clientdir}/iscsi-client.rb
%{yast_clientdir}/iscsi-client_*.rb
%{yast_clientdir}/inst_iscsi-client.rb
%{yast_moduledir}/IscsiClient.*
%{yast_moduledir}/IscsiClientLib.*
%{yast_desktopdir}/iscsi-client.desktop
%{yast_scrconfdir}/iscsid.scr
%doc %{yast_docdir}
%{yast_schemadir}/autoyast/rnc/iscsi-client.rnc
