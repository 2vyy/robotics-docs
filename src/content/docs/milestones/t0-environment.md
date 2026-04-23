---
title: "T0: Environment Setup"
---
## Objective
Get the simulation stack running on your machine.

## Steps

Follow the [Onboarding guide](/onboarding/) in order:

1. [Choose your platform](/onboarding/platform-choice) — get into Ubuntu 24.04
2. [Install ROS 2 Jazzy](/onboarding/ros-install) — run the automated setup script
3. [Verify your install](/onboarding/verify) — confirm all components are working
4. [Run a ROS 2 demo](/onboarding/first-demo) — talker/listener sanity check
5. [PX4 flight test (SITL)](/onboarding/px4-test) — full simulation with Gazebo and ROS 2

## Completion Criteria

- `ros2 --version` prints a version
- `gz sim shapes.sdf` opens a 3D window
- PX4 SITL launches and connects to the uXRCE-DDS agent
- `ros2 topic list` shows `/fmu/out/*` topics from the simulated drone
