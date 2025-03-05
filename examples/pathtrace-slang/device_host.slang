/*
 * Copyright (c) 2023-2025, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2023-2025, NVIDIA CORPORATION. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

module device_host;

// Note(nbickford): Is using a Slang module here unrealistic? This would usually
// be a .h file shared between both. I suppose we could, say, have Slang
// compile it to a CPU header, or write this so that it still works as a C++
// polyglot.
// Let's keep it as a module for now to give Slang modules the best opportunity.

public struct PushConstant {
  public int maxDepth;
  public int frame;
  public float fireflyClampThreshold;
  public int maxSamples;
};

public struct CameraInfo {
  public float4x4 projInv;
  public float4x4 viewInv;
};
