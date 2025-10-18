import 'package:flutter/material.dart';

import '../../models/shift_status.dart';
import '../../services/requests_api_service.dart';
import '../../theme/app_colors.dart';
import 'requests/advance_requests_tab.dart';
import 'requests/break_requests_tab.dart';
import 'requests/leave_requests_tab.dart';

class RequestsPage extends StatefulWidget {
	const RequestsPage({
		super.key,
		required this.employeeId,
		this.hideBreakTab = false,
	});

	final String employeeId;
	final bool hideBreakTab;

	@override
	State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> with SingleTickerProviderStateMixin {
	late final TabController _tabController;
	ShiftStatus? _shiftStatus;
	bool _shiftStatusLoading = false;

	@override
	void initState() {
		super.initState();
		final tabCount = widget.hideBreakTab ? 2 : 3;
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
			final status = await RequestsApiService.fetchShiftStatus(widget.employeeId);
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
			if (!widget.hideBreakTab) const Tab(icon: Icon(Icons.free_breakfast), text: 'الاستراحات'),
		];

		final views = <Widget>[
			LeaveRequestsTab(employeeId: widget.employeeId),
			AdvanceRequestsTab(employeeId: widget.employeeId),
			if (!widget.hideBreakTab)
				BreakRequestsTab(
					employeeId: widget.employeeId,
					shiftStatus: _shiftStatus,
					isShiftStatusLoading: _shiftStatusLoading,
					onShiftStatusChanged: () => _loadShiftStatus(showLoadingIndicator: false),
				),
		];

		return Scaffold(
			backgroundColor: AppColors.background,
			appBar: AppBar(
				title: const Text('طلبات الموظف'),
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
