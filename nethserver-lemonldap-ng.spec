Summary: NethServer configuration for LemonLDAP::NG
%define name nethserver-lemonldap-ng
%define version 0.1.0
%define release 1
Name: %{name}
Version: %{version}
Release: %{release}%{?dist}
License: GPL
Source: %{name}-%{version}.tar.gz
BuildArch: noarch
URL: https://github.com/danb35/nethserver-lemonldap-ng

BuildRequires: nethserver-devtools
Requires: lemonldap-ng lasso lasso-perl
Requires: nethserver-release = 7
#AutoReq: no

%description
NethServer configuration for LemonLDAP::NG
(https://lemonldap-ng.org/welcome/)

%prep
%setup

%post
%preun

%build
%{makedocs}
perl createlinks

%install
rm -rf $RPM_BUILD_ROOT
(cd root; find . -depth -print | cpio -dump $RPM_BUILD_ROOT)

%{genfilelist} %{buildroot} $RPM_BUILD_ROOT > default.lst

%clean
rm -rf $RPM_BUILD_ROOT

%files -f default.lst
%dir %{_nseventsdir}/%{name}-update

%changelog
* Thu Mar 18 2021 Dan Brown <dan@familybrown.org> 0.1.0-1.ns7
- Initial Release
