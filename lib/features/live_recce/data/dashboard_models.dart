part of 'recce_models.dart';

/// Milestone 3 model: the field dashboard, `GET /recce/dashboard` (backend recceReview.dashboard.ts `fieldDashboard`).
/// `completed` = approved by EVERY required stage on the CURRENT version (the server works it out; nothing is derived here).

/// One project row of the dashboard: the counts of the shops given to this login in that project.
class ProjectProgress {
  const ProjectProgress({
    required this.projectId,
    this.projectCode = '',
    this.projectName = '',
    this.assigned = 0,
    this.started = 0,
    this.submitted = 0,
    this.approved = 0,
    this.rework = 0,
    this.pending = 0,
  });

  final String projectId;
  final String projectCode;
  final String projectName;
  final int assigned;
  final int started;
  final int submitted;
  final int approved;
  final int rework;
  final int pending;

  /// The bar of this project: every assigned shop sits in exactly one part (see [ProgressBar]).
  ProgressBar get bar => ProgressBar.of(this);

  factory ProjectProgress.fromJson(Json j) => ProjectProgress(
        projectId: (j['projectId'] ?? '').toString(),
        projectCode: (j['projectCode'] ?? '').toString(),
        projectName: (j['projectName'] ?? '').toString(),
        assigned: _i(j['assigned']),
        started: _i(j['started']),
        submitted: _i(j['submitted']),
        approved: _i(j['approved']),
        rework: _i(j['rework']),
        pending: _i(j['pending']),
      );
}

/// Parts of one project bar. Approved and rework shops were submitted, submitted shops were started, started shops are assigned, so
/// the five parts add up to the assigned shops: approved, rework, other submitted (waiting for a reviewer), started but not yet
/// submitted, and not started.
class ProgressBar {
  const ProgressBar({this.approved = 0, this.rework = 0, this.inReview = 0, this.working = 0, this.notStarted = 0});

  final int approved;
  final int rework;
  final int inReview;
  final int working;
  final int notStarted;

  int get total => approved + rework + inReview + working + notStarted;

  static int _atLeast0(int v) => v < 0 ? 0 : v;

  factory ProgressBar.of(ProjectProgress p) => ProgressBar(
        approved: p.approved,
        rework: p.rework,
        inReview: _atLeast0(p.submitted - p.approved - p.rework),
        working: _atLeast0(p.started - p.submitted),
        notStarted: _atLeast0(p.assigned - p.started),
      );
}

class FieldDashboard {
  const FieldDashboard({
    this.assignedProjects = 0,
    this.assignedShops = 0,
    this.started = 0,
    this.submitted = 0,
    this.underReview = 0,
    this.approved = 0,
    this.rework = 0,
    this.completed = 0,
    this.pending = 0,
    this.avgCompletionHours,
    this.reworkCount = 0,
    this.reworkPercent = 0,
    this.projects = const [],
  });

  final int assignedProjects;
  final int assignedShops;
  final int started;
  final int submitted;
  final int underReview;
  final int approved;
  final int rework;
  final int completed;
  final int pending;

  /// Mean time from visit start to the last approval over completed shops; null when no shop is completed yet.
  final double? avgCompletionHours;

  /// Shops that ever had a rework or more-photos request (each once), and that count as a percent of the submitted shops.
  final int reworkCount;
  final double reworkPercent;
  final List<ProjectProgress> projects;

  factory FieldDashboard.fromJson(Json j) => FieldDashboard(
        assignedProjects: _i(j['assignedProjects']),
        assignedShops: _i(j['assignedShops']),
        started: _i(j['started']),
        submitted: _i(j['submitted']),
        underReview: _i(j['underReview']),
        approved: _i(j['approved']),
        rework: _i(j['rework']),
        completed: _i(j['completed']),
        pending: _i(j['pending']),
        avgCompletionHours: _d(j['avgCompletionHours']),
        reworkCount: _i(j['reworkCount']),
        reworkPercent: _d(j['reworkPercent']) ?? 0,
        projects: [for (final p in _ml(j['projects'])) ProjectProgress.fromJson(p)],
      );
}
