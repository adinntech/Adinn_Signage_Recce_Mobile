# Review classifications (11 canonical IDs)

11 canonical IDs are classified Review. These are canonical question IDs; the workbook has 483 source ROWS covering 65 canonical IDs. Rows per ID are counted below.

Rule: a Review question is not removed from the vendor form until explicitly approved. N/A / Not assessed is never treated as a safe installation (feasibility shows Requires Review).

| canonical_id | question | source rows | vendor decisions Needed/Not/Blank | dependency | current behaviour |
|---|---|---|---|---|---|
| structure_accessible | Is the proposed wall / structure accessible? | 10 | 0/10/0 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| fixing_surface_available | Is a suitable fixing surface available? | 10 | 0/10/0 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| ac_or_obstruction | Is there any AC unit or other obstruction? | 10 | 0/10/0 | feasibility review flag (Yes) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| location_approved_by_shop | Is the proposed location approved by the shop representative? | 10 | 0/10/0 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| excavation_permission | Excavation permission available? | 4 | 0/3/1 | twin checklist pole_excavation_allowed (feasibility review flag) | kept in the form (Installation Safety) |
| underground_utilities | Any underground cables / pipes suspected at pole location? | 8 | 0/6/2 | feasibility review flag (Yes / Not assessed) | kept in the form (Installation Safety) |
| pole_excavation_allowed | Is excavation for the pole footing permitted? | 4 | 0/3/1 | feasibility review flag (No) | kept in the form (Installation Safety) |
| area_free_of_obstruction | Is the board area free of obstructions? | 12 | 0/8/4 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| pole_configuration_confirmed | Is the pole configuration confirmed on site? | 4 | 0/2/2 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| door_opening_clearance | Is there clearance for door opening? | 3 | 0/3/0 | feasibility review flag (No) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
| moisture_exposure | Is the surface exposed to moisture? | 1 | 0/1/0 | feasibility review flag (Yes) | kept in the form, required, until the business approves removal (it raises a feasibility review flag; hiding it would make an unassessed site look obstruction-free) |
