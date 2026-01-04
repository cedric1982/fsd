#pragma once
#include <cmath>
#include <optional>

struct BearingResult {
    int heading_deg;      // 0..359
    double distance_m;    // for diagnostics
};

inline double deg2rad(double deg) { return deg * (M_PI / 180.0); }
inline double rad2deg(double rad) { return rad * (180.0 / M_PI); }

// Great-circle initial bearing from (lat1,lon1) to (lat2,lon2)
inline std::optional<BearingResult> bearing_deg(double lat1, double lon1,
                                                double lat2, double lon2)
{
    // Basic sanity
    if (!std::isfinite(lat1) || !std::isfinite(lon1) ||
        !std::isfinite(lat2) || !std::isfinite(lon2)) {
        return std::nullopt;
    }

    const double φ1 = deg2rad(lat1);
    const double φ2 = deg2rad(lat2);
    const double Δλ = deg2rad(lon2 - lon1);

    const double y = std::sin(Δλ) * std::cos(φ2);
    const double x = std::cos(φ1) * std::sin(φ2) -
                     std::sin(φ1) * std::cos(φ2) * std::cos(Δλ);

    if (x == 0.0 && y == 0.0) return std::nullopt;

    double θ = std::atan2(y, x);          // -pi..pi
    double brng = std::fmod(rad2deg(θ) + 360.0, 360.0);  // 0..360

    int hdg = static_cast<int>(std::lround(brng)) % 360;

    // Optional: distance (rough) for gating; haversine
    const double R = 6371000.0;
    const double dφ = deg2rad(lat2 - lat1);
    const double dλ = deg2rad(lon2 - lon1);
    const double a = std::sin(dφ/2)*std::sin(dφ/2) +
                     std::cos(φ1)*std::cos(φ2) * std::sin(dλ/2)*std::sin(dλ/2);
    const double c = 2 * std::atan2(std::sqrt(a), std::sqrt(1-a));
    double dist = R * c;

    return BearingResult{hdg, dist};
}
