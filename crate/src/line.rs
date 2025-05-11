use crate::types::{Color, HasCoords, Point};

pub struct Line {}

impl Line {
    pub fn get_vertex_data<P: HasCoords>(
        points_a: &P,
        point_b: &P,
        width: f32,
        color: Color,
    ) -> Vec<f32> {
        let half_width = width / 2.0;
        let parallel_angle = (point_b.y() - points_a.y()).atan2(point_b.x() - points_a.x());
        let angle = parallel_angle + std::f32::consts::PI / 2.0; // perpendicular angle
        let ax = points_a.x() - half_width * parallel_angle.cos();
        let ay = points_a.y() - half_width * parallel_angle.sin();
        let bx = point_b.x() + half_width * parallel_angle.cos();
        let by = point_b.y() + half_width * parallel_angle.sin();

        let vertex_data: [Point; 6] = [
            Point {
                x: ax - half_width * angle.cos(),
                y: ay - half_width * angle.sin(),
            },
            Point {
                x: ax + half_width * angle.cos(),
                y: ay + half_width * angle.sin(),
            },
            Point {
                x: bx + half_width * angle.cos(),
                y: by + half_width * angle.sin(),
            },
            Point {
                x: bx - half_width * angle.cos(),
                y: by - half_width * angle.sin(),
            },
            Point {
                x: ax - half_width * angle.cos(),
                y: ay - half_width * angle.sin(),
            },
            Point {
                x: bx + half_width * angle.cos(),
                y: by + half_width * angle.sin(),
            },
        ];

        vertex_data
            .iter()
            .flat_map(|point| {
                vec![
                    point.x, point.y, 0.0, 1.0, color.0, color.1, color.2, color.3,
                ]
            })
            .collect()
    }
}
