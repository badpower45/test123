import 'package:flutter/material.dart';

import '../../models/shift_status.dart';
import '../../services/requests_api_service.dart';
import '../../theme/app_colors.dart';
import 'requests/leave_requests_tab.dart';
import 'requests/advance_requests_tab.dart';
import 'requests/attendance_requests_tab.dart';
import 'requests/break_requests_tab.dart';

class ManagerSendRequestsPage extends StatefulWidget {
	const ManagerSendRequestsPage({
		super.key,
		required this.managerId,
		this.hideBreakTab = false,
	});

	final String managerId;
	final bool hideBreakTab;

	@override
	State<ManagerSendRequestsPage> createState() => _ManagerSendRequestsPageState();
}

class _ManagerSendRequestsPageState extends State<ManagerSendRequestsPage> with SingleTickerProviderStateMixin {
	Future<void> reloadData() async {
		await _loadShiftStatus(showLoadingIndicator: true);
	}
	late final TabController _tabController;
	ShiftStatus? _shiftStatus;
	bool _shiftStatusLoading = false;

	@override
	void initState() {
	  super.initState();
	  final tabCount = widget.hideBreakTab ? 3 : 4;
	  _tabController = TabController(length: tabCount, vsync: this);
	  if (!widget.hideBreakTab) {
	    _loadShiftStatus(showLoadingIndicator: true);
	  }
	}

	@override
	void dispose() {
		_tabController.dispose();
		super.dispose();
	}

	Future<void> _loadShiftStatus({bool showLoadingIndicator = false}) async {
		if (widget.hideBreakTab) {
			return;
		}
		if (mounted && (showLoadingIndicator || !_shiftStatusLoading)) {
			setState(() => _shiftStatusLoading = true);
		}
		try {
			final status = await RequestsApiService.fetchShiftStatus(widget.managerId);
			if (!mounted) {
				return;
			}
			setState(() {
				_shiftStatus = status;
				_shiftStatusLoading = false;
			});
		} catch (_) {
			if (!mounted) {
				return;
			}
			setState(() => _shiftStatusLoading = false);
		}
	}

	@override
	Widget build(BuildContext context) {
	  final tabs = <Tab>[
	    const Tab(icon: Icon(Icons.event_available), text: 'الإجازات'),
	    const Tab(icon: Icon(Icons.payments), text: 'السلف'),
	    const Tab(icon: Icon(Icons.edit_calendar), text: 'الحضور'),
	    if (!widget.hideBreakTab) const Tab(icon: Icon(Icons.free_breakfast), text: 'الاستراحات'),
	  ];

	  final views = <Widget>[
	    ManagerLeaveRequestsTab(managerId: widget.managerId),
	    ManagerAdvanceRequestsTab(managerId: widget.managerId),
	    ManagerAttendanceRequestsTab(managerId: widget.managerId),
	    if (!widget.hideBreakTab)
	      ManagerBreakRequestsTab(
	        managerId: widget.managerId,
	        shiftStatus: _shiftStatus,
	        isShiftStatusLoading: _shiftStatusLoading,
	        onShiftStatusChanged: () => _loadShiftStatus(showLoadingIndicator: false),
	      ),
	  ];

		return Scaffold(
			backgroundColor: AppColors.background,
			appBar: AppBar(
				title: const Text('إرسال طلبات'),
				centerTitle: true,
				backgroundColor: Colors.white,
				foregroundColor: AppColors.textPrimary,
				elevation: 0,
				bottom: TabBar(
					controller: _tabController,
					labelColor: AppColors.primaryOrange,
					unselectedLabelColor: AppColors.textSecondary,
					indicatorColor: AppColors.primaryOrange,
					tabs: tabs,
				),
			),
			body: TabBarView(
				controller: _tabController,
				children: views,
			),
		);
	}
}
