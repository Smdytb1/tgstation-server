﻿using System;

namespace Tgstation.Server.Api.Models
{
	/// <summary>
	/// Represents a long running job on the server
	/// </summary>
	[Model]
	public sealed class Job
	{
		/// <summary>
		/// The <see cref="Job"/> ID
		/// </summary>
		public long Id { get; set; }

		/// <summary>
		/// Human readable description of the <see cref="Job"/>
		/// </summary>
		public string Description { get; set; }

		/// <summary>
		/// When the <see cref="Job"/> was started
		/// </summary>
		public DateTimeOffset StartedAt { get; set; }

		/// <summary>
		/// When the <see cref="Job"/> stopped
		/// </summary>
		public DateTimeOffset StoppedAt { get; set; }

		/// <summary>
		/// If the <see cref="Job"/> was cancelled
		/// </summary>
		public bool Cancelled { get; set; }

		/// <summary>
		/// If the <see cref="Job"/> has incremental progress, this will range from 1 - 100. 0 otherwise
		/// </summary>
		public int Progress { get; set; }
	}
}
