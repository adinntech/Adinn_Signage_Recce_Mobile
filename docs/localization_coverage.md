# Localization coverage audit

Per file: **localized** = fixed UI literal with a Tamil entry; **missing** = fixed UI literal still without Tamil; **technical** = intentionally untranslated (GSB, NLB, GST, AR, PDF, 2D, 3D, units, symbols); **dynamic** = user content / ids / computed text, never translated. PDF tables are translated through `TamilReport` and verified by `test/tamil_pdf_test.dart`.

| file | localized | missing | technical | dynamic | ENG/அ |
|---|---:|---:|---:|---:|---|
| lib/core/widgets/common_widgets.dart | 2 | 2 | 0 | 14 | n/a |
| lib/features/references/media_reference_detail_screen.dart | 25 | 1 | 0 | 18 | yes |
| lib/app.dart | 1 | 0 | 0 | 0 | n/a |
| lib/core/widgets/language_switcher.dart | 0 | 0 | 0 | 1 | yes |
| lib/features/annotation/annotation_editor_screen.dart | 28 | 0 | 1 | 13 | yes |
| lib/features/annotation/photo_tour.dart | 0 | 0 | 0 | 7 | n/a |
| lib/features/approvals/approvals_screen.dart | 2 | 0 | 0 | 0 | yes |
| lib/features/approvals/review_screen.dart | 18 | 0 | 1 | 8 | yes |
| lib/features/ar/ar_editor_panels.dart | 38 | 0 | 0 | 15 | n/a |
| lib/features/ar/ar_preview_tab.dart | 33 | 0 | 0 | 17 | n/a |
| lib/features/ar/camera_ar_screen.dart | 1 | 0 | 0 | 1 | yes |
| lib/features/auth/forgot_pin_screen.dart | 9 | 0 | 0 | 4 | yes |
| lib/features/auth/login_screen.dart | 5 | 0 | 0 | 2 | n/a |
| lib/features/board/board_editor_screen.dart | 29 | 0 | 0 | 31 | yes |
| lib/features/board/board_picker.dart | 1 | 0 | 0 | 7 | n/a |
| lib/features/board/gst_field.dart | 1 | 0 | 0 | 2 | n/a |
| lib/features/board/installation_choice_card.dart | 0 | 0 | 0 | 2 | n/a |
| lib/features/board/installation_modes.dart | 9 | 0 | 0 | 5 | n/a |
| lib/features/board/media_tabs.dart | 3 | 0 | 0 | 3 | n/a |
| lib/features/board/quantity_size_section.dart | 15 | 0 | 2 | 6 | n/a |
| lib/features/board/site_questions_form.dart | 2 | 0 | 0 | 4 | n/a |
| lib/features/board/unit_notes_fields.dart | 0 | 0 | 0 | 2 | n/a |
| lib/features/board/units_screen.dart | 11 | 0 | 0 | 4 | yes |
| lib/features/compare/comparison_screen.dart | 19 | 0 | 0 | 7 | yes |
| lib/features/drawing/drawing_2d_screen.dart | 10 | 0 | 0 | 1 | yes |
| lib/features/gsb/gsb_override_sheet.dart | 9 | 0 | 0 | 3 | n/a |
| lib/features/gsb/gsb_type_sheet.dart | 4 | 0 | 0 | 1 | n/a |
| lib/features/history/activity_screen.dart | 0 | 0 | 0 | 5 | yes |
| lib/features/history/snapshot_view.dart | 6 | 0 | 2 | 5 | n/a |
| lib/features/history/version_history_screen.dart | 4 | 0 | 0 | 0 | yes |
| lib/features/home/dashboard_screen.dart | 2 | 0 | 0 | 9 | yes |
| lib/features/home/home_shell.dart | 1 | 0 | 1 | 2 | n/a |
| lib/features/home/shop_search.dart | 2 | 0 | 0 | 0 | n/a |
| lib/features/location/gps_widgets.dart | 5 | 0 | 0 | 3 | n/a |
| lib/features/model3d/technical_drawing_screen.dart | 2 | 0 | 0 | 3 | yes |
| lib/features/nlb/nlb_type_sheet.dart | 3 | 0 | 0 | 0 | n/a |
| lib/features/notes/other_spec_dialog.dart | 0 | 0 | 0 | 7 | n/a |
| lib/features/notes/voice_notes_section.dart | 9 | 0 | 0 | 5 | n/a |
| lib/features/panorama/panorama_list_screen.dart | 10 | 0 | 0 | 2 | yes |
| lib/features/panorama/panorama_viewer_screen.dart | 15 | 0 | 0 | 6 | yes |
| lib/features/photos/photo_section.dart | 17 | 0 | 0 | 6 | yes |
| lib/features/photos/photo_workspace_screen.dart | 10 | 0 | 0 | 5 | yes |
| lib/features/photos/site_photo_view.dart | 1 | 0 | 0 | 0 | n/a |
| lib/features/preview3d/preview_3d_screen.dart | 25 | 0 | 1 | 25 | yes |
| lib/features/preview_live/live_preview_tab.dart | 16 | 0 | 0 | 8 | n/a |
| lib/features/preview_live/preview_gallery.dart | 4 | 0 | 0 | 5 | yes |
| lib/features/profile/profile_screen.dart | 13 | 0 | 1 | 8 | yes |
| lib/features/projects/project_detail_screen.dart | 2 | 0 | 0 | 4 | yes |
| lib/features/projects/projects_screen.dart | 0 | 0 | 0 | 5 | yes |
| lib/features/projects/task_detail_screen.dart | 1 | 0 | 0 | 3 | yes |
| lib/features/references/media_reference_library_screen.dart | 1 | 0 | 0 | 1 | yes |
| lib/features/report/reports_screen.dart | 10 | 0 | 0 | 5 | yes |
| lib/features/review_comments/comment_widgets.dart | 9 | 0 | 0 | 6 | n/a |
| lib/features/review_comments/photo_comments_screen.dart | 14 | 0 | 0 | 7 | yes |
| lib/features/review_comments/shop_comments_screen.dart | 1 | 0 | 0 | 5 | yes |
| lib/features/shop/add_media_sheet.dart | 5 | 0 | 0 | 2 | n/a |
| lib/features/shop/shop_detail_screen.dart | 22 | 0 | 0 | 10 | yes |
| lib/features/shop/shop_form_screen.dart | 2 | 0 | 0 | 6 | yes |
| lib/features/shop/shop_tile.dart | 0 | 0 | 0 | 2 | n/a |
| lib/features/submission/submission_screen.dart | 10 | 0 | 1 | 2 | yes |
| lib/features/survey/checklist_form.dart | 11 | 0 | 0 | 11 | n/a |
| lib/features/survey/electrical_form.dart | 9 | 0 | 0 | 7 | n/a |
| lib/features/survey/feasibility.dart | 0 | 0 | 0 | 1 | n/a |
| lib/features/survey/measurement_form.dart | 10 | 0 | 0 | 11 | n/a |
| lib/features/survey/readiness.dart | 0 | 0 | 0 | 1 | n/a |
| lib/features/survey/site_markup_screen.dart | 33 | 0 | 1 | 21 | yes |
| lib/features/survey/unit_survey_screen.dart | 3 | 0 | 0 | 3 | yes |

Totals: localized 563, missing 3, technical 11, dynamic 395.
